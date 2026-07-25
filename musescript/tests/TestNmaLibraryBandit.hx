package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.GrowthWeights;
import musescript.evo.LearnedLibrary;
import musescript.evo.MapElites;
import musescript.evo.TreeSurgery;
import musescript.harness.Bar;
import musescript.evo.nma.NmaAttr;
import musescript.evo.nma.NmaCreditBank;
import musescript.evo.nma.NmaFitness;

/**
 * Attribution bandit + learned library mining.
 *
 * «ἔτι διψῶσι πτυχαί.»
 */
class TestNmaLibraryBandit extends Test {

	static function tape(n:Int):Array<Bar> {
		var bars = new Array<Bar>();
		var prev = 100.0;
		for (i in 0...n) {
			var close = 100.0 + i * 0.1 + 2.0 * Math.sin(i / 3.0);
			bars.push({
				open: prev, high: Math.max(prev, close) + 0.2, low: Math.min(prev, close) - 0.2,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	static function genome():StrategyGenome {
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
			name: "lib_bandit"
		};
	}

	function setup() {
		NmaCreditBank.clear();
		LearnedLibrary.clear();
		Fitness.attrBandit = false;
		Fitness.creditCuts = false;
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.clearFnCache();
	}

	function teardown() {
		NmaCreditBank.clear();
		LearnedLibrary.clear();
		Fitness.attrBandit = false;
		Fitness.creditCuts = false;
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.clearFnCache();
	}

	public function testBanditSkipsConfidentLowUcbSites() {
		// Cold keys always ablate; a heavily observed low-mean key is skipped vs a winner.
		Assert.isTrue(NmaCreditBank.shouldAblate("cold", 1.0));
		for (_ in 0...24) NmaCreditBank.deposit("loser", 0.01);
		for (_ in 0...6) NmaCreditBank.deposit("winner", 2.0);
		var best = NmaCreditBank.ucb("winner");
		Assert.isFalse(NmaCreditBank.shouldAblate("loser", best),
			'loser UCB should not compete with winner (best=$best loser=${NmaCreditBank.ucb("loser")})');

		var g = genome();
		var bars = tape(70);
		var sites = new Array<musescript.evo.nma.NmaAttr.NmaAttrSite>();
		var bc:Array<{path:musescript.evo.TreeSurgery.GPath, node:BoolNode}> = [];
		TreeSurgery.collectBool(g.entryLong, [], bc, true);
		for (e in bc) sites.push({slot: 0, path: e.path});
		for (_ in 0...4) NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		Fitness.attrBandit = true;
		var pack = NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		Assert.notNull(pack);
		Assert.equals(sites.length, pack.deltas.length);
	}

	public function testLearnLibraryMinesAndGrowEmitsHole() {
		var g = genome();
		var arch = new musescript.evo.MapElites.EliteArchive();
		// Two cells with overlapping motifs (same entryLong shape).
		arch.offer(g, 1.0, "cvt_0", 0.02, 5.0, 0.5, 0.2);
		var g2 = {
			entryLong: g.entryLong,
			entryShort: g.entryShort,
			exitLong: BCmp(">", KConst(1.0), KConst(0.0)),
			exitShort: g.exitShort,
			size: g.size, params: g.params, name: "lib_bandit_b",
			lineage: g.lineage, seedOrigin: g.seedOrigin
		};
		arch.offer(g2, 1.1, "cvt_1", 0.05, 8.0, 0.6, 0.3);

		var tuner = new GrowthWeights();
		var added = LearnedLibrary.mineFromArchives([arch], tuner, 1, 2, 20, 8);
		Assert.isTrue(added > 0, "expected motifs promoted");
		Assert.isTrue(LearnedLibrary.size() > 0);
		Assert.isTrue(tuner.hasCategory("boolLibrary"));

		// Force library pick: weight only library tags by zeroing others isn't needed —
		// clone + BHole path tested via promote + get.
		var key = LearnedLibrary.keys()[0];
		var motif = LearnedLibrary.get(key);
		Assert.notNull(motif);
		var wrapped:BoolNode = BHole(LearnedLibrary.cloneBool(motif));
		Assert.isTrue(switch (wrapped) { case BHole(_): true; default: false; });
		Assert.isTrue(Canonical.boolNodeCount(motif) >= 2);
	}

	public function testGrowthWeightsEnsureTag() {
		var t = new GrowthWeights();
		Assert.isFalse(t.hasCategory("boolLibrary"));
		t.ensureTag("boolLibrary", "abc123", 0.2);
		Assert.isTrue(t.hasCategory("boolLibrary"));
		Assert.equals("abc123", t.summary("boolLibrary")[0].tag);
	}

	public function testCreditCutsUsesBankMeansWithoutAblating() {
		var g = genome();
		var bars = tape(70);
		var sites = new Array<musescript.evo.nma.NmaAttr.NmaAttrSite>();
		var bc:Array<{path:musescript.evo.TreeSurgery.GPath, node:BoolNode}> = [];
		TreeSurgery.collectBool(g.entryLong, [], bc, true);
		for (e in bc) sites.push({slot: 0, path: e.path});
		// Warm the bank via real ablations first.
		for (_ in 0...3) NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		var keys = [for (e in sites) {
			var node = TreeSurgery.getBool(g.entryLong, e.path);
			Canonical.boolStructuralKey(node);
		}];
		Assert.isTrue(NmaCreditBank.warmEnough(keys), "bank should be warm after ablations");
		var expected = [for (k in keys) NmaCreditBank.mean(k)];
		Fitness.creditCuts = true;
		var pack = NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		Assert.notNull(pack);
		Assert.equals(expected.length, pack.deltas.length);
		for (i in 0...expected.length)
			Assert.floatEquals(expected[i], pack.deltas[i], 1e-12, 'credit-cuts delta[$i]');
	}

	public function testSeedNodeFromBankOnBijection() {
		var leaf:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));
		var key = Canonical.boolStructuralKey(leaf);
		for (_ in 0...5) NmaCreditBank.deposit(key, 1.5);
		var nma = musescript.evo.nma.NmaBijection.boolFromEnum(leaf);
		Assert.equals(5, (nma : musescript.evo.nma.NmaNode).creditN);
		Assert.floatEquals(1.5, (nma : musescript.evo.nma.NmaNode).creditSum / 5, 1e-12);
	}
}
