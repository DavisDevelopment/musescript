package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.compile.MuseCompiler;
import musescript.compile.MuseHostLower;
import musescript.compile.StrategyWasmBackend;
import musescript.evo.Expand;
import musescript.evo.BoolNode;
import musescript.evo.PanelAction;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;
import musescript.parse.MuseParser;

/**
 * Panel evo genomes: Expand emits literal `*_of("SYM",…)` / `fund_of` from
 * `SPanel`; with `PanelAction` emits HostABI `buy`/`sell_all`/`rebalance_equal`/
 * `target_weight` instead of `long`/`short`/`flat`. Variation grows both under
 * a fixed universe; optional WASM packing smoke for expanded panel-action source.
 */
class TestPanelEvoGenomes extends Test {
	static function panelGenome():StrategyGenome {
		return {
			name: "PanelMomCmp",
			params: [],
			entryLong: BCmp(">",
				KSeries(SPanel("mom", "AAA", null, 5)),
				KSeries(SPanel("mom", "BBB", null, 5))),
			entryShort: BCmp("<",
				KSeries(SPanel("close", "AAA", null, null)),
				KSeries(SPanel("sma", "BBB", null, 3))),
			exitLong: BCmp("<",
				KSeries(SPanel("rsi", "AAA", null, 5)),
				KConst(30.0)),
			exitShort: BCmp(">",
				KSeries(SPanel("fund", "AAA", "revenue", null)),
				KConst(2000.0)),
			size: KConst(1.0)
		};
	}

	static function withAction(g:StrategyGenome, a:PanelAction):StrategyGenome {
		return {
			name: g.name, params: g.params,
			entryLong: g.entryLong, entryShort: g.entryShort,
			exitLong: g.exitLong, exitShort: g.exitShort,
			size: g.size, panelAction: a
		};
	}

	public function testExpandEmitsPanelOfShapes() {
		var src = Expand.expand(panelGenome());
		Assert.isTrue(src.indexOf('mom_of("AAA", 5)') >= 0, src);
		Assert.isTrue(src.indexOf('mom_of("BBB", 5)') >= 0, src);
		Assert.isTrue(src.indexOf('close_of("AAA")') >= 0, src);
		Assert.isTrue(src.indexOf('sma_of("BBB", 3)') >= 0, src);
		Assert.isTrue(src.indexOf('rsi_of("AAA", 5)') >= 0, src);
		Assert.isTrue(src.indexOf('fund_of("AAA", "revenue")') >= 0, src);
		// v0 without PanelAction: still classic single-name skeleton
		Assert.isTrue(src.indexOf("long(") >= 0, src);
		Assert.isTrue(src.indexOf("short(") >= 0, src);
		Assert.isTrue(src.indexOf("flat()") >= 0, src);
		Assert.isTrue(src.indexOf("dict_new") < 0, src);
		Assert.isTrue(src.indexOf("bag_") < 0, src);
	}

	public function testExpandEmitsBuySellPanelAction() {
		var src = Expand.expand(withAction(panelGenome(), PABuy("AAA")));
		Assert.isTrue(src.indexOf('buy("AAA", 1)') >= 0, src);
		Assert.isTrue(src.indexOf('sell_all("AAA")') >= 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		Assert.isTrue(src.indexOf("short(") < 0, src);
		Assert.isTrue(src.indexOf("flat()") < 0, src);
		Assert.isTrue(src.indexOf('mom_of("AAA", 5)') >= 0, src);
	}

	public function testExpandEmitsRebalancePanelAction() {
		var src = Expand.expand(withAction(panelGenome(), PARebalance(["AAA", "BBB"])));
		Assert.isTrue(src.indexOf('rebalance_equal(["AAA", "BBB"])') >= 0, src);
		Assert.isTrue(src.indexOf('sell_all("AAA")') >= 0, src);
		Assert.isTrue(src.indexOf('sell_all("BBB")') >= 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
	}

	public function testExpandEmitsTargetWeightPanelAction() {
		var g = withAction(panelGenome(), PATargetWeight("BBB"));
		g.size = KConst(0.5);
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf('target_weight("BBB", 0.5)') >= 0, src);
		Assert.isTrue(src.indexOf('sell_all("BBB")') >= 0, src);
		Assert.isTrue(src.indexOf("flat()") < 0, src);
	}

	public function testVariationGrowsPanelOfUnderUniverse() {
		var v = new Variation(42);
		v.configureForUniverse(["AAA", "BBB"]);
		v.configureForTape([{
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: 0., index: 0,
			data: ["revenue" => 100.0]
		}]);
		var hit = false;
		for (i in 0...80) {
			var g = v.randomGenome(3);
			var src = Expand.expand(g);
			if (src.indexOf("_of(\"AAA\"") >= 0 || src.indexOf("_of(\"BBB\"") >= 0) {
				hit = true;
				break;
			}
		}
		Assert.isTrue(hit, "expected at least one grown genome with panel *_of under universe");
	}

	public function testVariationGrowsPanelActionsUnderUniverse() {
		var v = new Variation(7);
		v.configureForUniverse(["AAA", "BBB"]);
		var buyHit = false;
		var rebalHit = false;
		var twHit = false;
		for (i in 0...120) {
			var g = v.randomGenome(2);
			if (g.panelAction == null) continue;
			var src = Expand.expand(g);
			Assert.isTrue(src.indexOf("long(") < 0, src);
			Assert.isTrue(src.indexOf("flat()") < 0, src);
			switch (g.panelAction) {
				case PABuy(_):
					buyHit = true;
					Assert.isTrue(src.indexOf("buy(") >= 0, src);
					Assert.isTrue(src.indexOf("sell_all(") >= 0, src);
				case PARebalance(_):
					rebalHit = true;
					Assert.isTrue(src.indexOf("rebalance_equal([") >= 0, src);
				case PATargetWeight(_):
					twHit = true;
					Assert.isTrue(src.indexOf("target_weight(") >= 0, src);
			}
			if (buyHit && rebalHit && twHit) break;
		}
		Assert.isTrue(buyHit, "expected PABuy grown under universe");
		Assert.isTrue(rebalHit, "expected PARebalance grown under universe");
		Assert.isTrue(twHit, "expected PATargetWeight grown under universe");
	}

	public function testPanelOfExprHelper() {
		Assert.equals('close_of("X")', Expand.panelOfExpr("close", "X", null, null));
		Assert.equals('mom_of("X", 8)', Expand.panelOfExpr("mom", "X", null, 8));
		Assert.equals('fund_of("X", "pe")', Expand.panelOfExpr("fund", "X", "pe", null));
		Assert.equals('ema_of("X", 13)', Expand.panelOfExpr("ema", "X", null, 13));
	}

	#if (js || python)
	public function testExpandedPanelGenomeWasmSmoke() {
		if (!StrategyWasmBackend.hostReady()) return;
		// Hand-built MS with the same shapes Expand emits — compiles on WASM panel path.
		var src = '
			@strategy("panel-evo-smoke")
			@on(bar) {
				if (sym_available("AAA") && mom_of("AAA", 5) > mom_of("BBB", 5)
					&& ema_of("AAA", 3) > close_of("BBB"))
					buy("AAA", 1);
			}
		';
		var panel = densePanel(40, 7);
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(emitted.wat.indexOf("call $mom") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $ema") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0, emitted.wat);

		var h = new HarnessContext();
		h.resetForTrial(100000);
		h.panel = panel;
		var ex = MuseCompiler.compileEx(prog, { target: "wasm", strict: false });
		Assert.isTrue(ex.backend == "wasm" || ex.emitted);
		var r = ex.fn(h);
		Assert.isTrue(r.trades >= 0);
	}

	public function testExpandedPanelActionGenomeWasmSmoke() {
		if (!StrategyWasmBackend.hostReady()) return;
		var g = withAction({
			name: "PanelBuyEvo",
			params: [],
			entryLong: BCmp(">",
				KSeries(SPanel("mom", "AAA", null, 5)),
				KSeries(SPanel("mom", "BBB", null, 5))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<",
				KSeries(SPanel("rsi", "AAA", null, 5)),
				KConst(30.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0)
		}, PABuy("AAA"));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf('buy("AAA"') >= 0, src);
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(emitted.wat.indexOf("call $buy") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $sell_all") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0, emitted.wat);

		var panel = densePanel(40, 11);
		var h = new HarnessContext();
		h.resetForTrial(100000);
		h.panel = panel;
		var ex = MuseCompiler.compileEx(prog, { target: "wasm", strict: false });
		Assert.isTrue(ex.backend == "wasm" || ex.emitted);
		var r = ex.fn(h);
		Assert.isTrue(r.trades >= 0);

		// Rebalance template also HostABI-native
		var g2 = withAction(g, PARebalance(["AAA", "BBB"]));
		g2.name = "PanelRebalEvo";
		var src2 = Expand.expand(g2);
		var prog2 = MuseHostLower.lower(new MuseParser().parse(src2));
		var emitted2 = StrategyWasmBackend.emitOnBar(prog2);
		Assert.isTrue(emitted2.wat.indexOf("call $rebalance_equal") >= 0, emitted2.wat);
		Assert.isTrue(emitted2.wat.indexOf("call $host_eval") < 0, emitted2.wat);
	}
	#end

	static function densePanel(nBars:Int, seed:Int):PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		for (name in ["AAA", "BBB"]) {
			var bars:Array<Bar> = [];
			var price = name == "AAA" ? 100.0 : 80.0;
			var rng = seed + (name == "AAA" ? 1 : 99);
			for (i in 0...nBars) {
				rng = (rng * 1103515245 + 12345) & 0x7fffffff;
				var noise = ((rng % 1000) / 1000.0 - 0.5) * 0.03;
				var o = price;
				var c = price * (1 + noise);
				bars.push({
					open: o, high: Math.max(o, c) * 1.002, low: Math.min(o, c) * 0.998,
					close: c, volume: 1000.0, time: i * 1.0, index: i
				});
				price = c;
			}
			bySym.set(name, bars);
		}
		return PanelFeed.fromSymbolBars(bySym);
	}
}
