package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.Canonical;
import musescript.harness.BarFeed;

/**
 * Regression + new-feature coverage for musescript.evo's Variation/EvolutionEngine/Expand --
 * previously UNCOVERED by the main test suite entirely (every prior verification of this
 * package was standalone EvoProof.hx runs and throwaway probes, never wired into
 * `node build/js/tests.js`). That gap is exactly why two real bugs (BTrend's dir string never
 * matching Expand's `dir == "up"` check, and the JVM-target Fitness.evaluate stub silently
 * ignoring `bars` and faking a nodeCount-derived result) went unnoticed for as long as they did
 * -- neither would have failed a single existing assertion.
 */
class TestEvoVariation extends Test {
	static function baseGenome(entryLong:BoolNode):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
	}

	// ── regression: BTrend dir must render to the RIGHT word ──────────────────────────────

	public function testBTrendOverRendersAsRising() {
		var s:SeriesNode = SInd("sma", "close", 8, null);
		var g = baseGenome(BTrend("over", s, 5));
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "rising("), 'expected "rising(" in: $src');
		Assert.isFalse(StringTools.contains(src, "falling("), 'did not expect "falling(" in: $src');
	}

	public function testBTrendUnderRendersAsFalling() {
		var s:SeriesNode = SInd("sma", "close", 8, null);
		var g = baseGenome(BTrend("under", s, 5));
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "falling("), 'expected "falling(" in: $src');
		Assert.isFalse(StringTools.contains(src, "rising("), 'did not expect "rising(" in: $src');
	}

	// ── regression: Fitness.evaluate must actually be sensitive to `bars` ─────────────────

	public function testFitnessEvaluateIsSensitiveToBars() {
		var g = baseGenome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		var tapeA = BarFeed.synthetic(300, 1).all();
		var tapeB = BarFeed.synthetic(300, 99).all();
		var a = Fitness.evaluate(g, tapeA, "js", false);
		var b = Fitness.evaluate(g, tapeB, "js", false);
		Assert.isTrue(a.ok && b.ok);
		// Two DIFFERENT synthetic tapes (different seeds) must not produce byte-identical
		// trades/equity for a real crossover strategy -- this is exactly what the JVM
		// fake-fitness stub bug violated (identical output regardless of the bars passed in).
		Assert.isTrue(a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-6,
			'expected different tapes to produce different results: a=(${a.trades},${a.finalEquity}) b=(${b.trades},${b.finalEquity})');
	}

	// ── new: attribution-guided mutation prefers the low-impact node ──────────────────────

	public function testAttributedMutationPrefersTheRedundantNode() {
		// entryLong = criticalCross AND alwaysTrue -- the AND-with-true clause contributes
		// NOTHING (ablating it to "always true" changes nothing, since it already always
		// passes), while ablating the crossover condition to "always true" would make the
		// strategy enter on literally every bar -- a huge, real fitness difference. A sound
		// attribution mechanism should target the redundant `alwaysTrue` half far more often
		// than the real crossover half.
		var critical:BoolNode = BCross("over", SPrice("close"), SInd("sma", "close", 8, null));
		var redundant:BoolNode = BCmp(">", KConst(1.0), KConst(0.0)); // already always-true
		var g = baseGenome(BAnd(critical, redundant));

		var bars = BarFeed.synthetic(400, 7).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);

		var v = new Variation(42);
		var criticalTouched = 0;
		var redundantTouched = 0;
		var trials = 60;
		for (i in 0...trials) {
			var mutated = v.attributedPointMutate(g, evalFn, 1);
			var src = Expand.expand(mutated);
			// A touched-critical mutation loses the crossover(...) call entirely from source;
			// a touched-redundant mutation keeps crossover(...) but the "1 > 0" tautology is
			// replaced by something else (or the same shape by chance).
			var stillHasCross = StringTools.contains(src, "crossover(");
			if (!stillHasCross) criticalTouched++;
			else redundantTouched++;
		}
		Assert.isTrue(redundantTouched > criticalTouched,
			'expected the redundant node to be mutated more often (redundant=$redundantTouched critical=$criticalTouched over $trials trials)');
	}

	// ── new: risk-managed exits are reachable from growth and actually execute ────────────

	/** `growRiskExit` (Variation.hx) is a new growBool terminal -- previously every genome's exit
	 * conditions could ONLY be signal-reversal shapes (BCross/BCmp/BTrend), never a stop-loss/
	 * take-profit/time-stop. Statistical reachability check (matches this file's established
	 * pattern for `testAttributedMutationPrefersTheRedundantNode`): over enough random genomes at
	 * a depth that reaches terminals, at least one must contain a risk-exit leaf in its rendered
	 * source, AND that genome must actually run without error through Fitness.evaluate -- growth
	 * alone proves reachability, evaluate() proves the render+compile+execute path is sound.
	 */
	public function testRiskManagedExitIsReachableFromGrowthAndExecutes() {
		var v = new Variation(7);
		var found = false;
		var bars = BarFeed.synthetic(300, 11).all();
		for (i in 0...80) {
			var g = v.randomGenome(3);
			var src = Expand.expand(g);
			if (StringTools.contains(src, "unrealized_pnl_pct()") || StringTools.contains(src, "bars_in_trade()")) {
				found = true;
				var r = Fitness.evaluate(g, bars, "js", false);
				Assert.isTrue(r.ok, 'risk-exit genome failed to evaluate: ${r.error}\n$src');
			}
		}
		Assert.isTrue(found, "expected at least one risk-managed-exit genome across 80 random draws");
	}

	/** `growMultiOutputField` (Variation.hx) -- macd/bbands/stoch field access, a scalar terminal.
	 * Same reachability + execution discipline as the risk-exit test above. These always take the
	 * JS-fallback path (no native WASM lowering for macd/bbands/stoch), so "js" is the only
	 * backend this needs to prove sound. */
	public function testMultiOutputFieldIsReachableFromGrowthAndExecutes() {
		var v = new Variation(13);
		var found = false;
		var bars = BarFeed.synthetic(300, 5).all();
		for (i in 0...80) {
			var g = v.randomGenome(3);
			var src = Expand.expand(g);
			if (StringTools.contains(src, "macd(") || StringTools.contains(src, "bbands(") || StringTools.contains(src, "stoch(")) {
				found = true;
				var r = Fitness.evaluate(g, bars, "js", false);
				Assert.isTrue(r.ok, 'multi-output genome failed to evaluate: ${r.error}\n$src');
			}
		}
		Assert.isTrue(found, "expected at least one multi-output-field genome across 80 random draws");
	}

	// ── new: attribution-guided crossover protects the important recipient node ───────────

	/** Mirrors testAttributedMutationPrefersTheRedundantNode's exact idea, applied to crossover's
	 * RECIPIENT-side site selection: entryLong = criticalCross AND alwaysTrue. Attribution-guided
	 * crossover should overwrite the redundant half far more often than the critical crossover half,
	 * across many trials -- exactly like the mutation-targeting test, just via
	 * attributedSubtreeCrossover instead of attributedPointMutate. */
	public function testAttributedCrossoverProtectsTheCriticalNode() {
		var critical:BoolNode = BCross("over", SPrice("close"), SInd("sma", "close", 8, null));
		var redundant:BoolNode = BCmp(">", KConst(1.0), KConst(0.0)); // already always-true
		var g1 = baseGenome(BAnd(critical, redundant));
		// Donor genome: distinct BoolNode subtrees to splice in, so a successful splice is
		// detectable (donor content differs from anything already in g1).
		var g2 = baseGenome(BCmp("<", KConst(5.0), KConst(9.0)));

		var bars = BarFeed.synthetic(400, 7).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);

		var v = new Variation(21);
		var criticalTouched = 0;
		var redundantTouched = 0;
		var trials = 60;
		for (i in 0...trials) {
			var child = v.attributedSubtreeCrossover(g1, g2, evalFn);
			var src = Expand.expand(child);
			var stillHasCross = StringTools.contains(src, "crossover(");
			if (!stillHasCross) criticalTouched++;
			else redundantTouched++;
		}
		Assert.isTrue(redundantTouched > criticalTouched,
			'expected the redundant node to be overwritten more often (redundant=$redundantTouched critical=$criticalTouched over $trials trials)');
	}

	/** Correctness floor: the crossover-produced child must actually differ from g1 at least
	 * sometimes (donor content really gets spliced in, not silently ignored) and must always
	 * render/execute without error -- a real end-to-end check, not just structural inspection. */
	public function testAttributedCrossoverProducesValidExecutableGenomes() {
		var g1 = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(0.0)));
		var g2 = baseGenome(BTrend("over", SInd("ema", "close", 13, null), 5));
		var bars = BarFeed.synthetic(300, 17).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);
		var v = new Variation(9);
		var changed = false;
		for (i in 0...20) {
			var child = v.attributedSubtreeCrossover(g1, g2, evalFn);
			var r = Fitness.evaluate(child, bars, "js", false);
			Assert.isTrue(r.ok, 'crossover child failed to evaluate: ${r.error}\n${Expand.expand(child)}');
			if (Canonical.structuralKey(child) != Canonical.structuralKey(g1)) changed = true;
		}
		Assert.isTrue(changed, "expected at least one crossover call to actually change the genome");
	}

	// ── new: EvolutionEngine's mutation pressure ramps up under stagnation ────────────────

	public function testMutationPressureRampsUnderStagnation() {
		var engine = new EvolutionEngine(1, 12, 2, 3);
		var pop = engine.seedPopulation(2);
		Assert.floatEquals(0.3, engine.currentMutateProb()); // baseline, zero stagnant gens yet
		// A FLAT fitness landscape (every genome scores identically) can never produce a new
		// best, so this must drive stagnantGens up every step() call AFTER the first -- the
		// first call's fitness always counts as "the first improvement" (lastBest starts at
		// -Infinity, and any real fitness beats that), so 8 calls give 7 stagnant generations.
		var flatFitness = [for (_ in pop) 0.5];
		var lastPop = pop;
		for (_ in 0...8) lastPop = engine.step(lastPop, flatFitness);
		Assert.equals(7, engine.stagnantGens);
		Assert.floatEquals(0.3 + 7 * 0.05, engine.currentMutateProb());
		Assert.equals(12, lastPop.length); // population size stays stable under repeated stagnation

		// A genuine improvement resets the counter back to zero immediately.
		var improvedFitness = [for (_ in lastPop) 5.0];
		engine.step(lastPop, improvedFitness);
		Assert.equals(0, engine.stagnantGens);
		Assert.floatEquals(0.3, engine.currentMutateProb());

		// The ramp is capped, not unbounded -- stays sane after very long stagnation.
		for (_ in 0...50) lastPop = engine.step(lastPop, flatFitness);
		Assert.isTrue(engine.currentMutateProb() <= 0.85);
	}

	// ── new: genome-expanded entries don't pyramid on a sticky condition ──────────────────

	/**
	 * Regression for a real bug: a STICKY entry condition (unlike a transient crossover, which
	 * fires once) used to re-fire `long`/`short` on every single bar it stayed true, pyramiding
	 * the position unbounded (confirmed via a standalone OrderSim probe -- see
	 * TestOrderBook.testPyramidedLongTracksWeightedAverageEntryPrice for the cost-basis half of
	 * this same bug). Fixed in Expand.hx by guarding entries on `position()`. This is the
	 * genome-EXPANSION-level check: entryLong is UNCONDITIONALLY true (never fires exitLong), so
	 * a naive expansion would enter on literally every bar -- the guard must cap it at exactly one
	 * entry fill for the whole run.
	 */
	public function testStickyAlwaysTrueEntryDoesNotPyramid() {
		var g = baseGenome(BCmp(">", KConst(1.0), KConst(0.0))); // always true, every bar
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "position() <= 0"), 'expected the entry guard in: $src');

		var bars = BarFeed.synthetic(200, 3).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok);
		Assert.equals(1, r.trades, 'expected exactly ONE entry fill despite entryLong being true every bar, got ${r.trades}');
	}

	/** A same-bar-repeatable EXIT condition is unaffected by the entry guard (exits were never the
	 * bug) -- flat() still fires whenever exitLong/exitShort holds, unconditionally, matching
	 * pre-existing (correct) behavior. */
	public function testExitGuardUnaffectedByEntryFix() {
		var g:StrategyGenome = {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)), // always true
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(1.0), KConst(0.0)), // ALSO always true -- immediate flat every bar
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
		var bars = BarFeed.synthetic(50, 3).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok);
		// Enter (position<=0 true, guard passes), immediately flat every bar -- so trades should be
		// exactly 2 per bar-cycle (enter+exit), not zero and not unboundedly growing.
		Assert.isTrue(r.trades > 0 && r.trades < 200, 'expected bounded enter/exit trade count, got ${r.trades}');
	}
}
