package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.evo.Canonical;
import musescript.evo.TreeSurgery;
import musescript.evo.TreeSurgery.GPath;
import musescript.harness.Bar;
import musescript.evo.nma.NmaAttr;
import musescript.evo.nma.NmaAttr.NmaAttrSite;
import musescript.evo.nma.NmaFitness;
import musescript.evo.nma.NmaSurgery;
import musescript.evo.nma.NmaDirtySpine;
import musescript.evo.nma.NmaBool;
import musescript.evo.nma.NmaBool.NmaBAnd;

/**
 * Dirty-spine sibling memo identity + speculative K-replacement batch scoring.
 *
 * «Βάκχου λύσις· λύρας χορδαὶ θρόον ἵεσαν.»
 */
class TestNmaDirtySpineSpecGrowth extends Test {

	static function tape(n:Int):Array<Bar> {
		var bars = new Array<Bar>();
		var prev = 100.0;
		for (i in 0...n) {
			var t = i / 5.0;
			var close = 100.0 + i * 0.12 + 5.0 * Math.sin(t);
			bars.push({
				open: prev, high: Math.max(prev, close) + 0.4, low: Math.min(prev, close) - 0.4,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	function nestedGenome():StrategyGenome {
		return {
			entryLong: BAnd(
				BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
				BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))
			),
			entryShort: FALSE_BOOL,
			exitLong: BCross("under", SPrice("close"), SInd("sma", "close", 5, null)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "dirty_spine"
		};
	}

	function setup() {
		Fitness.preferNma = false;
		Fitness.nmaDirtySpine = false;
		Fitness.speculativeGrowthK = 1;
		Fitness.speculativeGrowthWindows = 4;
		Fitness.speculativeGrowthWindowLambda = 0.5;
		Fitness.speculativeGrowthMinDelta = 0.0;
		Fitness.speculativeGrowthParsimonyLambda = 0.01;
		Fitness.nmaTape = null;
		Fitness.creditCuts = false;
		Fitness.clearFnCache();
	}

	function teardown() {
		Fitness.preferNma = false;
		Fitness.nmaDirtySpine = false;
		Fitness.speculativeGrowthK = 1;
		Fitness.speculativeGrowthWindows = 4;
		Fitness.speculativeGrowthWindowLambda = 0.5;
		Fitness.speculativeGrowthMinDelta = 0.0;
		Fitness.speculativeGrowthParsimonyLambda = 0.01;
		Fitness.nmaTape = null;
		Fitness.creditCuts = false;
		Fitness.clearFnCache();
	}

	public function testSiblingMemoSurvivesSpineReplace() {
		var g = nestedGenome();
		var bars = tape(80);
		var built = NmaFitness.prepare(g, bars);
		Assert.notNull(built);
		var fr0 = NmaFitness.evaluatePrepared(built.nma, built.ctx, bars);
		Assert.isTrue(fr0.ok);
		var andNode = cast(built.nma.entryLong, NmaBAnd);
		var sib = andNode.b;
		var sibSeries = sib.lastSeries;
		var sibEpoch = sib.evalEpoch;
		Assert.notNull(sibSeries);
		Assert.isTrue(sibEpoch >= 0);

		var always = NmaAttr.alwaysTrueNma();
		var path:GPath = [TreeSurgery.GStep.StepA];
		var newRoot = NmaSurgery.replaceBool(built.nma.entryLong, path, always);
		built.nma.entryLong = newRoot;
		var fr1 = NmaFitness.evaluatePrepared(built.nma, built.ctx, bars);
		Assert.isTrue(fr1.ok);
		Assert.equals(sibSeries, sib.lastSeries);
		Assert.equals(sibEpoch, sib.evalEpoch);
	}

	public function testWorkingCopyHitAfterPut() {
		var g = nestedGenome();
		var bars = tape(60);
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = true;
		Fitness.beginNmaWorking();
		var fr0 = Fitness.evaluate(g, bars);
		Assert.isTrue(fr0.ok);
		Assert.equals(1, Fitness.nmaWorkingPuts);
		Assert.equals(0, Fitness.nmaWorkingHits);
		var fr1 = Fitness.evaluate(g, bars);
		Assert.isTrue(fr1.ok);
		Assert.equals(1, Fitness.nmaWorkingHits);
		Assert.floatEquals(fr0.sharpe, fr1.sharpe, 1e-9);
	}

	public function testWorkingCopyRejectsSameLengthDifferentTape() {
		var g = nestedGenome();
		var barsA = tape(60);
		var barsB = tape(60);
		for (i in 0...barsB.length) barsB[i].close += 25.0 + i * 0.01;
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = true;
		Fitness.beginNmaWorking();
		Assert.isTrue(Fitness.evaluate(g, barsA).ok);
		var hitsBefore = Fitness.nmaWorkingHits;
		var warmB = Fitness.evaluate(g, barsB);
		Assert.isTrue(warmB.ok);
		Assert.equals(hitsBefore, Fitness.nmaWorkingHits,
			"same length is not enough: different tape must miss the working copy");
		Fitness.nmaDirtySpine = false;
		var coldB = Fitness.evaluate(g, barsB);
		Assert.floatEquals(coldB.sharpe, warmB.sharpe, 1e-9);
	}

	public function testSpliceRegistersChildWorking() {
		var g = nestedGenome();
		var bars = tape(60);
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = true;
		Fitness.nmaTape = bars;
		Fitness.beginNmaWorking();
		Assert.isTrue(Fitness.evaluate(g, bars).ok);
		var parent = Fitness.nmaWorking.get(Canonical.structuralKey(g));
		Assert.notNull(parent);
		var repl:BoolNode = BCmp("<", KConst(0.0), KConst(1.0));
		var childEnum:StrategyGenome = {
			entryLong: BAnd(repl, BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))),
			entryShort: g.entryShort,
			exitLong: g.exitLong,
			exitShort: g.exitShort,
			size: g.size,
			params: [],
			name: "child",
			lineage: [],
			seedOrigin: null
		};
		var path:GPath = [TreeSurgery.GStep.StepA];
		var pack = NmaDirtySpine.spliceAndRegister(parent, 0, path, repl, childEnum);
		Assert.notNull(pack);
		var hitsBefore = Fitness.nmaWorkingHits;
		var fr = Fitness.evaluate(childEnum, bars);
		Assert.isTrue(fr.ok);
		Assert.equals(hitsBefore + 1, Fitness.nmaWorkingHits);
	}

	public function testSpliceRejectsLogicalMismatch() {
		var g = nestedGenome();
		var bars = tape(60);
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = true;
		Fitness.beginNmaWorking();
		Assert.isTrue(Fitness.evaluate(g, bars).ok);
		var parent = Fitness.workingGet(Canonical.structuralKey(g));
		Assert.notNull(parent);
		var actual:BoolNode = BCmp("<", KConst(0.0), KConst(1.0));
		var wrong:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
		var child:StrategyGenome = {
			entryLong: BAnd(actual, BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))),
			entryShort: g.entryShort,
			exitLong: g.exitLong,
			exitShort: g.exitShort,
			size: g.size,
			params: [],
			name: "mismatch",
			lineage: [],
			seedOrigin: null
		};
		var path:GPath = [TreeSurgery.GStep.StepA];
		Assert.isNull(NmaDirtySpine.spliceAndRegister(parent, 0, path, wrong, child),
			"dirty-spine must fail closed when NMA splice differs from normalized enum child");
	}

	public function testBoolReplacementScoresParity() {
		var g = nestedGenome();
		var bars = tape(80);
		var site:NmaAttrSite = { slot: 0, path: [TreeSurgery.GStep.StepA] };
		var repls:Array<BoolNode> = [
			BCmp(">", KConst(1.0), KConst(0.0)),
			BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(40.0)),
			BCross("over", SPrice("close"), SInd("sma", "close", 8, null))
		];
		var batch = NmaAttr.boolReplacementScores(g, site, repls, bars);
		Assert.notNull(batch);
		Assert.equals(3, batch.length);
		for (i in 0...repls.length) {
			var child:StrategyGenome = {
				entryLong: BAnd(repls[i], BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))),
				entryShort: g.entryShort,
				exitLong: g.exitLong,
				exitShort: g.exitShort,
				size: g.size,
				params: [],
				name: 'r$i',
				lineage: [],
				seedOrigin: null
			};
			var solo = Fitness.score(NmaFitness.evaluate(child, bars), 1);
			Assert.floatEquals(solo, batch[i], 1e-6);
		}
	}

	public function testRobustReplacementScoresIncludeParentGate() {
		var g = nestedGenome();
		var bars = tape(80);
		var site:NmaAttrSite = { slot: 0, path: [TreeSurgery.GStep.StepA] };
		var identical:BoolNode = BCross(
			"over", SPrice("close"), SInd("sma", "close", 5, null));
		var different:BoolNode = BCmp(
			">", KSeries(SInd("rsi", "close", 5, null)), KConst(45.0));
		var pack = NmaAttr.boolReplacementRobustScores(
			g, site, [identical, different], bars, 4, 0.5, 0.01);
		Assert.notNull(pack);
		Assert.equals(2, pack.scores.length);
		Assert.floatEquals(pack.baseline, pack.scores[0], 1e-9,
			"replacing a site with itself must equal the parent robust score");
	}

	public function testPruneKeepsPopKeysAcrossGen() {
		var g = nestedGenome();
		var bars = tape(60);
		Fitness.preferNma = true;
		Fitness.nmaDirtySpine = true;
		Fitness.beginNmaWorking();
		Assert.isTrue(Fitness.evaluate(g, bars).ok);
		Assert.equals(1, Fitness.nmaWorkingPuts);
		var key = Canonical.structuralKey(g);
		Fitness.pruneNmaWorking([key]);
		Assert.equals(0, Fitness.nmaWorkingHits);
		Assert.isTrue(Fitness.evaluate(g, bars).ok);
		Assert.equals(1, Fitness.nmaWorkingHits, "prune must retain pack so next evaluate hits");
	}
}
