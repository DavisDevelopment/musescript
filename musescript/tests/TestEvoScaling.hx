package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
import musescript.evo.Rand;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.EvolutionEngine;
import musescript.evo.nma.NmaFitness;
import musescript.harness.Bar;
import musescript.harness.BarFeed;

/**
 * Guards for the scaling work on the serial generation tail and the NMA tape path.
 *
 * Every optimization here is meant to be EXACT — same species, same novelty, same fitness — so the
 * tests are equivalence tests against the shape each one replaced, not smoke tests that merely
 * check the new code runs. An approximate speciation or a novelty score that drifts would silently
 * change what evolves, which is a far worse outcome than being slow.
 */
class TestEvoScaling extends Test {

	static function genome(entry:BoolNode, ?name:String = "g"):StrategyGenome {
		return {
			entryLong: entry,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: [],
			seedOrigin: null
		};
	}

	/** A spread of structurally different genomes, deterministic across runs. */
	static function population(n:Int):Array<StrategyGenome> {
		var rng = new Rand(7);
		var inds = ["sma", "ema", "rsi", "atr", "wma"];
		var out:Array<StrategyGenome> = [];
		for (i in 0...n) {
			var leaf:BoolNode = BCross("over", SPrice("close"),
				SInd(inds[rng.int(inds.length)], "close", 3 + rng.int(20), null));
			var depth = rng.int(4);
			for (_ in 0...depth) {
				leaf = switch (rng.int(3)) {
					case 0: BAnd(leaf, BCmp(">", KSeries(SPrice("close")), KConst(rng.float() * 10)));
					case 1: BOr(leaf, BTrend("over", SPrice("high"), 2 + rng.int(5)));
					default: BNot(leaf);
				};
			}
			out.push(genome(leaf, 'g$i'));
		}
		return out;
	}

	// ── Canonical: the unboxed shape vector must be the Map signature, exactly ────────────

	public function testShapeVectorMatchesSignature() {
		for (g in population(40)) {
			var vec = Canonical.shapeVector(g);
			var sig = Canonical.shapeSignature(g);
			var total = 0;
			for (i in 0...vec.length) total += vec[i];
			Assert.equals(total, Canonical.shapeVectorTotal(vec));
			// The Map is now derived from the vector, so agreement on the total plus a
			// round-trip through both distance functions is what pins them together.
			var sum = 0;
			for (k => v in sig) sum += v;
			Assert.equals(total, sum, 'signature counts must sum to the vector total for ${g.name}');
		}
	}

	public function testShapeVectorDistanceEqualsMapDistance() {
		var pop = population(30);
		for (i in 0...pop.length) {
			for (j in 0...pop.length) {
				var viaMap = Canonical.shapeDistance(Canonical.shapeSignature(pop[i]), Canonical.shapeSignature(pop[j]));
				var viaVec = Canonical.shapeVectorDistance(Canonical.shapeVector(pop[i]), Canonical.shapeVector(pop[j]));
				Assert.equals(viaMap, viaVec, 'distance parity for ${pop[i].name}/${pop[j].name}');
			}
		}
	}

	/**
	 * The admissible prefilter speciation relies on: Manhattan distance is bounded below by the
	 * difference of the totals. If this ever fails, speciation would start SKIPPING genuine
	 * matches, silently splitting species and changing selection pressure.
	 */
	public function testTotalDifferenceBoundsDistance() {
		var pop = population(30);
		for (i in 0...pop.length) {
			for (j in 0...pop.length) {
				var a = Canonical.shapeVector(pop[i]);
				var b = Canonical.shapeVector(pop[j]);
				var totalGap = Canonical.shapeVectorTotal(a) - Canonical.shapeVectorTotal(b);
				if (totalGap < 0) totalGap = -totalGap;
				Assert.isTrue(totalGap <= Canonical.shapeVectorDistance(a, b),
					'|Σa-Σb| must never exceed the Manhattan distance (${pop[i].name}/${pop[j].name})');
			}
		}
	}

	// ── MapElites: bounded k-selection must equal collect-then-sort ──────────────────────

	/** The shape `noveltyDistance` replaced: every distance, sorted, mean of the k smallest. */
	static function noveltyBySorting(archive:EliteArchive, tradesPerBar:Float, avgHold:Float,
			longFrac:Float, k:Int, dutyCycle:Float, creditConc:Float):Float {
		var dists:Array<Float> = [];
		for (c in archive.entries()) {
			var cell = c.cell;
			var dTrade = (tradesPerBar - cell.tradesPerBar) / 0.1;
			var dHold = (avgHold - cell.avgHold) / 20.0;
			var dBias = (longFrac - cell.longFrac);
			var dDuty = (dutyCycle - cell.dutyCycle);
			var dCred = (creditConc - cell.creditConc);
			dists.push(Math.sqrt(dTrade * dTrade + dHold * dHold + dBias * dBias + dDuty * dDuty + dCred * dCred));
		}
		if (dists.length == 0) return 0.0;
		dists.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var n = Std.int(Math.min(k, dists.length));
		var sum = 0.0;
		for (i in 0...n) sum += dists[i];
		return sum / n;
	}

	public function testNoveltyTopKMatchesSortedMean() {
		var archive = new EliteArchive();
		var rng = new Rand(11);
		var pop = population(1);
		// Fill enough cells that the k-window has to evict, including a nearly-empty archive on
		// the way up (fewer occupied cells than k is the edge the old `min(k, len)` handled).
		var checkpoints = [0, 1, 2, 3, 9, 40];
		var offered = 0;
		for (target in checkpoints) {
			while (offered < target) {
				var tpb = rng.float() * 0.3;
				var hold = rng.float() * 60;
				var bias = rng.float();
				var duty = rng.float();
				archive.offer(pop[0], rng.float() * 4 - 2,
					MapElites.cellKey(tpb, hold, bias) + "_" + offered, tpb, hold, bias, duty, rng.float());
				offered++;
			}
			for (_ in 0...12) {
				var qT = rng.float() * 0.3, qH = rng.float() * 60, qB = rng.float();
				var qD = rng.float(), qC = rng.float();
				for (k in [1, 3, 5]) {
					Assert.floatEquals(
						noveltyBySorting(archive, qT, qH, qB, k, qD, qC),
						archive.noveltyDistance(qT, qH, qB, k, qD, qC),
						1e-12,
						'novelty parity at ${archive.size()} cells, k=$k');
				}
			}
		}
	}

	public function testNoveltyEmptyArchiveIsZero() {
		var archive = new EliteArchive();
		Assert.floatEquals(0.0, archive.noveltyDistance(0.1, 5.0, 0.5, 3, 0.2, 0.0), 1e-12);
	}

	// ── NmaFitness: the per-tape state cache must not change a single number ─────────────

	static function tape(n:Int):Array<Bar> return BarFeed.synthetic(n, 5).all();

	static function columnarGenome():StrategyGenome {
		return genome(BAnd(
			BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
			BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))
		), "tape_state");
	}

	public function testTapeStateReuseIsResultIdentical() {
		NmaFitness.clearColumnCache();
		var g = columnarGenome();
		var bars = tape(120);
		var first = NmaFitness.evaluate(g, bars);
		var second = NmaFitness.evaluate(g, bars); // same array object -> reference fast path
		Assert.isTrue(first.ok && second.ok);
		Assert.equals(first.trades, second.trades);
		Assert.floatEquals(first.finalEquity, second.finalEquity, 1e-12);
		Assert.floatEquals(first.sharpe, second.sharpe, 1e-12);
	}

	/**
	 * Same seed + same cheap oracle ⇒ identical population keys after `step`.
	 * Guards the variation/attribution allocation cuts (double-copy splice, donor-path skip,
	 * identity remap) against RNG or ranking drift.
	 */
	public function testStepSameSeedSameKeys() {
		function keysOf(seed:Int):Array<String> {
			var e = new EvolutionEngine(seed, 16, 2, 3);
			var pop = e.seedPopulation(3);
			function evalFn(g:StrategyGenome):Float return Canonical.nodeCount(g) * 1.0;
			var fit = [for (g in pop) evalFn(g)];
			var next = e.step(pop, fit, evalFn, 1.0, 2);
			return [for (g in next) Canonical.structuralKey(g)];
		}
		var a = keysOf(99);
		var b = keysOf(99);
		Assert.equals(a.length, 16);
		Assert.same(a, b);
	}

	public function testEqualButDistinctTapeArrayAgrees() {
		NmaFitness.clearColumnCache();
		var g = columnarGenome();
		var bars = tape(120);
		var viaOriginal = NmaFitness.evaluate(g, bars);
		// A different array OBJECT holding the same bars: the reference check misses, the content
		// hash matches, and the answer must be the same either way.
		var copy = [for (b in bars) b];
		var viaCopy = NmaFitness.evaluate(g, copy);
		Assert.isTrue(viaOriginal.ok && viaCopy.ok);
		Assert.equals(viaOriginal.trades, viaCopy.trades);
		Assert.floatEquals(viaOriginal.finalEquity, viaCopy.finalEquity, 1e-12);
	}

	public function testDifferentTapeDoesNotReuseColumns() {
		NmaFitness.clearColumnCache();
		var g = columnarGenome();
		var shortRun = NmaFitness.evaluate(g, tape(90));
		var longRun = NmaFitness.evaluate(g, tape(240));
		Assert.isTrue(shortRun.ok && longRun.ok);
		// Independent evidence that the second run re-derived its own tape rather than reading a
		// stale one: a longer tape must produce its own (different) outcome.
		Assert.isFalse(shortRun.finalEquity == longRun.finalEquity && shortRun.trades == longRun.trades,
			"a different tape must not serve the previous tape's columns");
	}

	public function testColumnarMatchesCompiledUnderTapeReuse() {
		NmaFitness.clearColumnCache();
		var g = columnarGenome();
		var bars = tape(140);
		var wasPrefer = Fitness.preferNma;
		Fitness.preferNma = false;
		var compiled = Fitness.evaluateCompiled(g, bars, "js", false, 0.0);
		Fitness.preferNma = wasPrefer;
		// Twice, so the assertion covers the warm (cached tape state) path as well as the cold one.
		for (_ in 0...2) {
			var nma = NmaFitness.evaluate(g, bars);
			Assert.isTrue(nma.ok, 'nma ok (${nma.error})');
			Assert.equals(compiled.trades, nma.trades, "trades parity");
			Assert.floatEquals(compiled.finalEquity, nma.finalEquity, 1e-9, "equity parity");
		}
	}
}
