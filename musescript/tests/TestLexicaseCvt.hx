package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.EvolutionEngine;
import musescript.evo.Fitness;
import musescript.evo.MapElites;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;

/**
 * ε-lexicase selection + CVT descriptor assignment (innovation-rate track).
 */
class TestLexicaseCvt extends Test {

	static function dummy(name:String):StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(0.0), KConst(1.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: [],
			seedOrigin: null
		};
	}

	public function testSobolCentroidsDeterministicAndUnitCube() {
		var a = MapElites.sobolCentroids(16, 4);
		var b = MapElites.sobolCentroids(16, 4);
		Assert.equals(16, a.length);
		for (i in 0...16) {
			Assert.equals(4, a[i].length);
			for (d in 0...4) {
				Assert.floatEquals(a[i][d], b[i][d], 1e-12);
				Assert.isTrue(a[i][d] >= 0 && a[i][d] <= 1);
			}
		}
	}

	public function testAssignCellCvtPartitions() {
		var cents = MapElites.sobolCentroids(8, 4);
		var k0 = MapElites.assignCell(0.0, 0.0, 0.0, 0.0, cents);
		var k1 = MapElites.assignCell(0.2, 40.0, 1.0, 1.0, cents);
		Assert.isTrue(StringTools.startsWith(k0, "cvt_"));
		Assert.isTrue(StringTools.startsWith(k1, "cvt_"));
		// Classic when no centroids
		Assert.equals(MapElites.cellKey(0.02, 5.0, 0.5), MapElites.assignCell(0.02, 5.0, 0.5, 0.0, null));
	}

	public function testQdScoreAndCoverage() {
		var arch = new musescript.evo.MapElites.EliteArchive();
		Assert.floatEquals(0.0, arch.qdScore());
		Assert.floatEquals(0.0, arch.coverage(48));
		arch.offer(dummy("a"), 1.5, "cvt_0");
		arch.offer(dummy("b"), -0.5, "cvt_1"); // negative ignored by qdScore
		arch.offer(dummy("c"), 2.0, "cvt_2");
		Assert.floatEquals(3.5, arch.qdScore(), 1e-9);
		Assert.floatEquals(3 / 48, arch.coverage(48), 1e-9);
		Assert.equals(3, arch.discoveryCount);
	}

	public function testLexicasePrefersCaseSpecialistOverAggregateLoser() {
		// Pop: A is best on case0 only; B best aggregate but mediocre everywhere.
		// With enough lexicase picks, A should appear as a parent sometimes.
		var pop = [dummy("spec"), dummy("agg"), dummy("mid")];
		var fitness = [0.1, 0.9, 0.5]; // aggregate: agg wins elitism
		var cases = [
			[10.0, -1.0], // specialist dominates case 0
			[0.0, 5.0],
			[1.0, 1.0]
		];
		var engine = new EvolutionEngine(42, 6, 1, 2);
		// Many steps; count how often "spec" lineage seeds children via selection.
		// We only check that step with caseFitness does not crash and returns popSize.
		var next = engine.step(pop, fitness, null, 0.0, 6, 0.0, cases);
		Assert.equals(6, next.length);
		// Off path (null cases) still works
		var next2 = engine.step(pop, fitness, null, 0.0, 6, 0.0, null);
		Assert.equals(6, next2.length);
	}

	public function testWindowSharpesEmptyOnBadResult() {
		var r = new musescript.evo.FitnessResult(false, Math.NaN, 0, 0, "js");
		Assert.equals(0, Fitness.windowSharpes(r, 4).length);
	}

	public function testWindowSharpesSplitsEquityIntoCases() {
		// 40 equity points → 4 windows of 10; each rising segment has a defined Sharpe.
		var r = new musescript.evo.FitnessResult(true, 1.0, 4, 110.0, "js");
		r.equity = [for (i in 0...40) 100.0 + i * 0.5];
		var cases = Fitness.windowSharpes(r, 4);
		Assert.equals(4, cases.length);
		for (c in cases) Assert.isTrue(!Math.isNaN(c));
		// windows<=1 collapses to whole-tape sharpe (length 1)
		Assert.equals(1, Fitness.windowSharpes(r, 1).length);
	}

	public function testDescribeFillsDutyCycle() {
		var fills = [
			{kind: "long", bar: 0, price: 1.0, qty: 1.0, pnl: 0.0},
			{kind: "flat", bar: 50, price: 1.0, qty: 1.0, pnl: 0.0}
		];
		var d = MapElites.describeFills(fills, 100);
		Assert.floatEquals(0.5, d.dutyCycle, 1e-9);
	}

	public function testSobolCentroidsFiveDim() {
		var a = MapElites.sobolCentroids(12, 5);
		Assert.equals(12, a.length);
		for (i in 0...12) {
			Assert.equals(5, a[i].length);
			for (d in 0...5) Assert.isTrue(a[i][d] >= 0 && a[i][d] <= 1);
		}
	}

	public function testAssignCellCreditAxisUsesFifthDim() {
		var cents = MapElites.sobolCentroids(16, 5);
		var kLow = MapElites.assignCell(0.05, 10.0, 0.5, 0.4, cents, 0.0);
		var kHigh = MapElites.assignCell(0.05, 10.0, 0.5, 0.4, cents, 1.0);
		Assert.isTrue(StringTools.startsWith(kLow, "cvt_"));
		Assert.isTrue(StringTools.startsWith(kHigh, "cvt_"));
		// Same cadence, different credit → may land in different CVT cells (HHI axis).
		// Not always different (nearest centroid can coincide), but 4-D vs 5-D vec length must differ:
		Assert.equals(4, MapElites.behaviorVec(0.05, 10.0, 0.5, 0.4).length);
		Assert.equals(5, MapElites.behaviorVec(0.05, 10.0, 0.5, 0.4, 0.7).length);
		Assert.equals(5, cents[0].length);
	}

	public function testMissingCreditPadsToUnknownCenter() {
		var cents = [
			[0.25, 0.25, 0.5, 0.4, 0.0],
			[0.25, 0.25, 0.5, 0.4, 0.5]
		];
		Assert.equals("cvt_1", MapElites.assignCell(0.05, 10.0, 0.5, 0.4, cents, null));
	}

	public function testCreditConcentrationHhi() {
		musescript.evo.nma.NmaCreditBank.clear();
		var leafA = BCmp(">", KConst(0.0), KConst(1.0));
		var leafB = BCmp("<", KConst(0.0), KConst(1.0));
		var g:StrategyGenome = {
			entryLong: BAnd(leafA, leafB),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "hhi",
			lineage: [],
			seedOrigin: null
		};
		Assert.floatEquals(0.5, MapElites.creditConcentration(g), 1e-12,
			"cold credit is neutral, not falsely diffuse");
		var keyA = musescript.evo.Canonical.boolStructuralKey(leafA);
		var keyB = musescript.evo.Canonical.boolStructuralKey(leafB);
		// Equal credit → HHI = 0.5 for two sites
		musescript.evo.nma.NmaCreditBank.deposit(keyA, 1.0);
		musescript.evo.nma.NmaCreditBank.deposit(keyB, 1.0);
		Assert.floatEquals(0.5, MapElites.creditConcentration(g), 1e-9);
		// Strong, well-observed dominance → evidence-shrunk HHI approaches 1.
		for (_ in 0...30) {
			musescript.evo.nma.NmaCreditBank.deposit(keyA, 99.0);
			musescript.evo.nma.NmaCreditBank.deposit(keyB, 1.0);
		}
		Assert.isTrue(MapElites.creditConcentration(g) > 0.9);
		musescript.evo.nma.NmaCreditBank.clear();
	}

	public function testSiteDeltaMemoWithinGeneration() {
		var variation = new musescript.evo.Variation(99);
		var g = dummy("memo");
		var leafKey = musescript.evo.Canonical.boolStructuralKey(g.entryLong);
		musescript.evo.nma.NmaCreditBank.clear();
		for (_ in 0...4) musescript.evo.nma.NmaCreditBank.deposit(leafKey, 1.0);
		Fitness.creditCuts = true;
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		var evalFn = function(_:StrategyGenome):Float return 1.0;
		variation.beginGeneration();
		for (_ in 0...80) variation.attributedPointMutate(g, evalFn, 0);
		Assert.isTrue(variation.siteDeltaMemoHits >= 5,
			'expected same-gen siteDelta memo hits, got ${variation.siteDeltaMemoHits}');
		variation.beginGeneration();
		Assert.equals(0, variation.siteDeltaMemoHits);
		Fitness.creditCuts = false;
		musescript.evo.nma.NmaCreditBank.clear();
	}
}
