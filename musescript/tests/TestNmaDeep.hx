package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.FillHash;
import musescript.evo.TreeSurgery;
import musescript.harness.Bar;
import musescript.evo.nma.NmaAttr;
import musescript.evo.nma.NmaCreditBank;
import musescript.evo.nma.NmaSemantic;
import musescript.evo.nma.NmaSemanticRdo;
import musescript.evo.nma.NmaFitness;
import musescript.evo.graal.EvoCache;

/**
 * P2 credit bank + semantic-RDO + fill-hash dedup telemetry.
 *
 * «βάκχευε· βάθος ἄβυσσον.»
 */
class TestNmaDeep extends Test {

	static function tape(n:Int):Array<Bar> {
		var bars = new Array<Bar>();
		var prev = 100.0;
		for (i in 0...n) {
			var close = 100.0 + i * 0.15 + 3.0 * Math.sin(i / 4.0);
			bars.push({
				open: prev, high: Math.max(prev, close) + 0.3, low: Math.min(prev, close) - 0.3,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	function setup() {
		NmaCreditBank.clear();
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.semanticRdoProb = 0;
		Fitness.clearFnCache();
	}

	function teardown() {
		NmaCreditBank.clear();
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.semanticRdoProb = 0;
		Fitness.clearFnCache();
	}

	public function testCreditBankSurvivesAcrossSessions() {
		var g:StrategyGenome = {
			entryLong: BAnd(
				BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
				BCmp(">", KSeries(SInd("rsi", "close", 5, null)), KConst(30.0))
			),
			entryShort: FALSE_BOOL,
			exitLong: BCross("under", SPrice("close"), SInd("sma", "close", 5, null)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "credit_bank"
		};
		Assert.isTrue(NmaFitness.supportsColumnar(g));
		var bars = tape(80);
		var sites = new Array<musescript.evo.nma.NmaAttr.NmaAttrSite>();
		var bc:Array<{path:musescript.evo.TreeSurgery.GPath, node:BoolNode}> = [];
		TreeSurgery.collectBool(g.entryLong, [], bc, true);
		for (e in bc) sites.push({slot: 0, path: e.path});
		Assert.isTrue(sites.length >= 2);

		var pack = NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		Assert.notNull(pack);

		var leaf = TreeSurgery.getBool(g.entryLong, sites[0].path);
		var key = Canonical.boolStructuralKey(leaf);
		Assert.isTrue(NmaCreditBank.observations(key) >= 1, "credit deposited for site 0");
		var mean1 = NmaCreditBank.mean(key);

		// Second session deposits again (bank is process-wide).
		NmaAttr.boolSiteDeltas(g, sites, bars, 0);
		Assert.isTrue(NmaCreditBank.observations(key) >= 2);
		Assert.floatEquals(mean1, NmaCreditBank.mean(key), 1e-9); // same deltas → same mean
	}

	public function testDesiredLongAndHamming() {
		var bars = tape(40);
		var d = NmaSemantic.desiredLong(bars, 5, 0);
		Assert.equals(40, d.length);
		Assert.floatEquals(0.0, d.at(39), 1e-12); // no forward window
		var rate = NmaSemantic.hammingRate(d, d);
		Assert.floatEquals(0.0, rate, 1e-12);
	}

	public function testSemanticRdoMutateReturnsGenome() {
		var g:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SPrice("close")), KConst(100.0)),
			entryShort: FALSE_BOOL,
			exitLong: BCmp("<", KSeries(SPrice("close")), KConst(90.0)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "rdo_mut"
		};
		var bars = tape(60);
		Fitness.preferNma = true;
		Fitness.nmaTape = bars;
		Fitness.nmaCostBps = 0;
		var rng = { float: function() return 0.1, int: function(n:Int) return 0 };
		var out = NmaSemanticRdo.tryMutate(g, function(_) return BCmp(">", KConst(1.0), KConst(0.0)), rng, 1, 3);
		Assert.notNull(out);
		Assert.notEquals(Canonical.structuralKey(g), Canonical.structuralKey(out));
	}

	public function testFillHashStableAndEvoCacheSemanticIndex() {
		var fills = [
			{kind: "long", bar: 1, price: 1.0, qty: 1.0, pnl: 0.0},
			{kind: "flat", bar: 5, price: 1.1, qty: 1.0, pnl: 0.1}
		];
		var h1 = FillHash.of(fills);
		var h2 = FillHash.of(fills);
		Assert.equals(h1, h2);
		// Price change must not change hash
		var fills2 = [
			{kind: "long", bar: 1, price: 9.0, qty: 2.0, pnl: 0.0},
			{kind: "flat", bar: 5, price: 8.0, qty: 2.0, pnl: 1.0}
		];
		Assert.equals(h1, FillHash.of(fills2));

		var cache = new EvoCache();
		cache.put("aaaa", {trades: 1, sharpe: 1.0, finalEquity: 1.0, fillHash: h1});
		cache.put("bbbb", {trades: 1, sharpe: 1.0, finalEquity: 1.0, fillHash: h1});
		Assert.equals(1, cache.uniqueSemantics);
		Assert.equals(1, cache.semanticHits);
		Assert.equals("aaaa", cache.keyForFillHash(h1));
	}

	public function testTreeSurgeryGetBool() {
		var n:BoolNode = BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0)));
		var leaf = TreeSurgery.getBool(n, [musescript.evo.TreeSurgery.GStep.StepB]);
		Assert.isTrue(switch (leaf) {
			case BCmp("<", _, _): true;
			default: false;
		});
	}
}
