package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.evo.TreeSurgery;
import musescript.evo.TreeSurgery.GPath;import musescript.harness.Bar;
import musescript.evo.nma.NmaAttr;
import musescript.evo.nma.NmaAttr.NmaAttrSite;
import musescript.evo.nma.NmaFitness;

/**
 * P1c+ dirty-spine attribution: `NmaAttr.boolSiteDeltas` must match per-ablation `evalFn` deltas
 * on pure market-data genomes (oracle ranking signal parity).
 *
 * «ἔκστασις ἁρπάζει νοῦν· θεὸς ἀντὶ ἀνθρώπου.»
 */
class TestNmaAttr extends Test {

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

	function setup() {
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.clearFnCache();
	}

	function teardown() {
		Fitness.preferNma = false;
		Fitness.nmaTape = null;
		Fitness.clearFnCache();
	}

	public function testBoolSiteDeltasMatchEvalFnAblations() {
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
			name: "attr_spine"
		};
		Assert.isTrue(NmaFitness.supportsColumnar(g));
		var bars = tape(100);
		var cost = 0.0;

		var sites = new Array<NmaAttrSite>();
		function add(slot:Int, root:BoolNode) {
			var bc:Array<{path:GPath, node:BoolNode}> = [];
			TreeSurgery.collectBool(root, [], bc, true);
			for (e in bc) sites.push({ slot: slot, path: e.path });
		}
		add(0, g.entryLong); add(1, g.entryShort); add(2, g.exitLong); add(3, g.exitShort);
		Assert.isTrue(sites.length >= 3, "expected nested bool sites");

		var alwaysTrue:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
		function evalFn(x:StrategyGenome):Float {
			var fr = Fitness.evaluateCompiled(x, bars, "js", false, cost);
			return (fr.ok && fr.trades >= 1 && !Math.isNaN(fr.sharpe) && fr.bankrupt != true)
				? fr.sharpe : Fitness.NEG_INF;
		}
		var baseline = evalFn(g);
		var refDeltas = [for (e in sites) {
			var ablated = withBoolRepl(g, e.slot, e.path, alwaysTrue);
			baseline - evalFn(ablated);
		}];

		var pack = NmaAttr.boolSiteDeltas(g, sites, bars, cost);
		Assert.notNull(pack, "NMA attr pack");
		Assert.floatEquals(baseline, pack.baseline, 1e-9, "baseline oracle score");
		Assert.equals(refDeltas.length, pack.deltas.length);
		for (i in 0...refDeltas.length) {
			if (refDeltas[i] == Fitness.NEG_INF || pack.deltas[i] == Fitness.NEG_INF) {
				Assert.equals(refDeltas[i], pack.deltas[i], 'delta[$i] NEG_INF parity');
			} else {
				Assert.floatEquals(refDeltas[i], pack.deltas[i], 1e-6, 'delta[$i]');
			}
		}
	}

	static function withBoolRepl(g:StrategyGenome, slot:Int, path:GPath, repl:BoolNode):StrategyGenome {
		return switch (slot) {
			case 0: {
				entryLong: TreeSurgery.replaceBoolWithBool(g.entryLong, path, repl),
				entryShort: g.entryShort, exitLong: g.exitLong, exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			case 1: {
				entryLong: g.entryLong,
				entryShort: TreeSurgery.replaceBoolWithBool(g.entryShort, path, repl),
				exitLong: g.exitLong, exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			case 2: {
				entryLong: g.entryLong, entryShort: g.entryShort,
				exitLong: TreeSurgery.replaceBoolWithBool(g.exitLong, path, repl),
				exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			case 3: {
				entryLong: g.entryLong, entryShort: g.entryShort, exitLong: g.exitLong,
				exitShort: TreeSurgery.replaceBoolWithBool(g.exitShort, path, repl),
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			default: g;
		};
	}
}
