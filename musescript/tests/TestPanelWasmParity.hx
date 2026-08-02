package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.TradeBuiltins;
import musescript.compile.MuseCompiler;
import musescript.compile.MuseHostLower;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StrategyWasmEmitter;
import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;

/**
 * Panel linear-memory v1 parity gate: literal-symbol panel reads lower natively
 * (no host_eval for close_of/mom_of/sma_of/sym_available), pack from PanelFeed,
 * and match interp trades / equity / sharpe on synthetic universes.
 */
class TestPanelWasmParity extends Test {
	/** Dual-name momentum flip — portfolio apply may host_eval; reads must be native. */
	static final PANEL_SCAN_SRC = '
		@strategy("panel-wasm-scan")
		@on(bar) {
			var mA = mom_of("AAA", 5);
			var mB = mom_of("BBB", 5);
			var sA = sma_of("AAA", 3);
			var cB = close_of("BBB");
			var okA = sym_available("AAA");
			var okB = sym_available("BBB");
			if (okA && okB && mA > mB && sA > cB) buy("AAA", 1);
			if (okA && okB && mB > mA) buy("BBB", 1);
		}
	';

	static function densePanel(nBars:Int, seed:Int):PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		for (name in ["AAA", "BBB"]) {
			var bars:Array<Bar> = [];
			var price = name == "AAA" ? 100.0 : 80.0;
			var rng = seed + (name == "AAA" ? 1 : 99);
			for (i in 0...nBars) {
				rng = (rng * 1103515245 + 12345) & 0x7fffffff;
				var noise = ((rng % 1000) / 1000.0 - 0.5) * 0.03;
				var drift = name == "AAA" ? Math.sin(i / 9.0) * 0.008 : Math.cos(i / 7.0) * 0.008;
				var o = price;
				var c = price * (1 + noise + drift);
				bars.push({
					open: o, high: Math.max(o, c) * 1.002, low: Math.min(o, c) * 0.998,
					close: c, volume: 1000.0 + (rng % 500), time: i * 1.0, index: i
				});
				price = c;
			}
			bySym.set(name, bars);
		}
		return PanelFeed.fromSymbolBars(bySym);
	}

	/** Sparse universe: CCC missing on even sessions (sym_available false). */
	static function sparsePanel(nBars:Int):PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		for (name in ["AAA", "CCC"]) {
			var bars:Array<Bar> = [];
			var price = name == "AAA" ? 50.0 : 60.0;
			for (i in 0...nBars) {
				if (name == "CCC" && (i % 2) == 0) continue; // gap → NaN after align
				var o = price;
				var c = price * (1 + (name == "AAA" ? 0.01 : -0.008) * Math.sin(i / 5.0));
				bars.push({
					open: o, high: Math.max(o, c) * 1.001, low: Math.min(o, c) * 0.999,
					close: c, volume: 500.0, time: i * 1.0, index: i
				});
				price = c;
			}
			bySym.set(name, bars);
		}
		return PanelFeed.fromSymbolBars(bySym);
	}

	static function panelWithAux():PanelFeed {
		var bySym = new Map<String, Array<Bar>>();
		var aaa:Array<Bar> = [];
		var bbb:Array<Bar> = [];
		for (i in 0...40) {
			aaa.push({
				open: 10.0 + i * 0.1, high: 10.5 + i * 0.1, low: 9.5 + i * 0.1,
				close: 10.2 + i * 0.1, volume: 100.0, time: i * 1.0, index: i,
				data: i >= 5 ? ["revenue" => 2000.0 + i] : null
			});
			bbb.push({
				open: 20.0 + i * 0.05, high: 20.5 + i * 0.05, low: 19.5 + i * 0.05,
				close: 20.1 + i * 0.05, volume: 80.0, time: i * 1.0, index: i
			});
		}
		bySym.set("AAA", aaa);
		bySym.set("BBB", bbb);
		return PanelFeed.fromSymbolBars(bySym);
	}

	function assertNoPanelReadHostEval(wat:String):Void {
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $mom") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $sma") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $lookback_ohlcv") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0,
			"panel scan reads+buy must not host_eval; got escapes in:\n" + wat);
	}

	function runInterp(src:String, panel:PanelFeed):Dynamic {
		TradeBuiltins.resetCrossState();
		var h = new HarnessContext();
		h.resetForTrial(100000);
		return new MuseInterp(h).runPanelBacktest(new MuseParser().parse(src), panel);
	}

	function runWasm(src:String, panel:PanelFeed):Dynamic {
		#if (js || python)
		if (!StrategyWasmBackend.hostReady()) return null;
		TradeBuiltins.resetCrossState();
		var h = new HarnessContext();
		h.resetForTrial(100000);
		Reflect.setField(h, "panel", panel);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "wasm", strict: false });
		Assert.isTrue(ex.backend == "wasm" || ex.emitted, "expected wasm emit, got " + ex.backend);
		h.panel = panel;
		return ex.fn(h);
		#else
		return null;
		#end
	}

	function assertParity(src:String, panel:PanelFeed):Void {
		var interpR = runInterp(src, panel);
		Assert.isTrue(interpR.trades >= 0);
		#if (js || python)
		var wasmR = runWasm(src, panel);
		if (wasmR == null) return;
		Assert.equals(interpR.trades, wasmR.trades);
		Assert.floatEquals(interpR.finalEquity, wasmR.finalEquity);
		Assert.floatEquals(interpR.sharpe, wasmR.sharpe);
		#end
	}

	public function testEmitNoHostEvalForPanelReads() {
		var prog = MuseHostLower.lower(new MuseParser().parse(PANEL_SCAN_SRC));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		assertNoPanelReadHostEval(emitted.wat);
		// buy may escape; panel reads must not be the only reason for host_eval.
		var keys = StrategyWasmBackend.featureKeysFromStrings(emitted.strings);
		Assert.isTrue(keys.indexOf("close@AAA") >= 0 || keys.indexOf("close@BBB") >= 0, keys.join(","));
		Assert.isTrue(emitted.wat.indexOf("call $mom") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $sma") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $lookback_ohlcv") >= 0, emitted.wat);
		// Panel reads are native call sites; buy may still host_eval.
		Assert.isTrue(emitted.wat.indexOf("call $mom") >= 0);
	}

	public function testDenseUniverseParity() {
		assertParity(PANEL_SCAN_SRC, densePanel(80, 11));
	}

	public function testSparseSymAvailableParity() {
		var src = '
			@strategy("panel-sparse")
			@on(bar) {
				var mA = mom_of("AAA", 4);
				var mC = mom_of("CCC", 4);
				if (sym_available("AAA") && (!sym_available("CCC") || mA > mC)) buy("AAA", 1);
				if (sym_available("CCC") && mC > mA) buy("CCC", 1);
			}
		';
		var emitted = StrategyWasmBackend.emitOnBar(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(emitted);
		Assert.isTrue(emitted.wat.indexOf("call $mom") >= 0, emitted.wat);
		assertParity(src, sparsePanel(60));
	}

	public function testAuxPanelSlotMatchesBarDataPit() {
		var panel = panelWithAux();
		var src = '
			@strategy("panel-aux")
			@on(bar) {
				if (sym_available("AAA") && !na(fund_of("AAA", "revenue")) && fund_of("AAA", "revenue") > 2010)
					buy("AAA", 1);
			}
		';
		var emitted = StrategyWasmBackend.emitOnBar(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(emitted);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0
			|| emitted.wat.indexOf("lookback_ohlcv") >= 0, emitted.wat);
		var keys = StrategyWasmBackend.featureKeysFromStrings(emitted.strings);
		Assert.isTrue(keys.indexOf("revenue@AAA") >= 0, keys.join(","));

		var tapes = StrategyWasmBackend.featureTapesFromCtx(null, emitted.strings, null, panel);
		var revIdx = keys.indexOf("revenue@AAA");
		Assert.isTrue(revIdx >= 0);
		Assert.isTrue(Math.isNaN(tapes[revIdx][0]));
		Assert.isTrue(Math.isNaN(tapes[revIdx][4]));
		Assert.floatEquals(2005.0, tapes[revIdx][5]);

		// Bare single-symbol revenue on AAA bars agrees with panel slot at aligned times.
		var aaaBars = panelFromSym(panel, "AAA");
		var bare = StrategyWasmBackend.auxColumnFromBars(aaaBars, "revenue");
		for (i in 0...bare.length) {
			if (Math.isNaN(bare[i])) Assert.isTrue(Math.isNaN(tapes[revIdx][i]));
			else Assert.floatEquals(bare[i], tapes[revIdx][i]);
		}
		assertParity(src, panel);
	}

	static function panelFromSym(panel:PanelFeed, sym:String):Array<Bar> {
		var out:Array<Bar> = [];
		for (t in 0...panel.length()) {
			var c = panel.closes[t].exists(sym) ? panel.closes[t].get(sym) : Math.NaN;
			var data:Map<String, Float> = null;
			if (panel.auxFieldNames != null) {
				for (name in panel.auxFieldNames) {
					var byT = panel.auxSeries.get(name);
					var m = byT != null && t < byT.length ? byT[t] : null;
					var v = m != null && m.exists(sym) ? m.get(sym) : Math.NaN;
					if (!Math.isNaN(v)) {
						if (data == null) data = new Map();
						data.set(name, v);
					}
				}
			}
			out.push({
				open: panel.opens[t].get(sym), high: panel.highs[t].get(sym),
				low: panel.lows[t].get(sym), close: c,
				volume: panel.volumes[t].get(sym), time: panel.times[t], index: t,
				data: data
			});
		}
		return out;
	}

	public function testBagsStillEscapeHonestly() {
		var src = '
			@strategy("panel-bags")
			@on(bar) {
				var b = bag_equal(["AAA", "BBB"]);
				rebalance_equal(bag_symbols(b));
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		// Opaque bag return → whole-module null, or host_eval — both honest.
		if (emitted == null) {
			Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_equal") >= 0);
			return;
		}
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") >= 0
			|| emitted.escapeRegions.length > 0);
	}

	public function testEscapeListDocumented() {
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_rank_mom") >= 0);
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("rebalance_equal") >= 0);
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("symbols") >= 0);
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_graph") >= 0);
	}
}
