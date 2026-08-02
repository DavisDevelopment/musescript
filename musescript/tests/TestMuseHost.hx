package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.MuseHost;
import musescript.compile.ClassStrategyLower;
import musescript.compile.MuseCompiler;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StrategyWasmEmitter;
import musescript.evo.BoolNode;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.Palette;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.evo.nma.NmaFitness;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import musescript.ast.Decl;
import musescript.builtins.TradeBuiltins;

/**
 * Namespaced `muse.*` host stdlib: parity with flat builtins, Strat `this.*`
 * sugar lowering, fund-aware palette gating, and WASM HostABI for lowered ops.
 */
class TestMuseHost extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int, ?data:Map<String, Float>):Bar {
		return {
			open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i,
			data: data
		};
	}

	static function risingBars(n:Int):Array<Bar> {
		return [for (i in 0...n) bar(100 + i, 101 + i, 99 + i, 100.5 + i, 1000, i)];
	}

	static function barsWithRevenue(n:Int):Array<Bar> {
		return [for (i in 0...n) bar(100 + i, 101 + i, 99 + i, 100.5 + i, 1000, i,
			i >= 2 ? ["revenue" => 1000.0 + i, "pe" => 12.0 + i * 0.1] : null)];
	}

	static function genome(entryLong:BoolNode):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
	}

	public function testResolveFlatMap() {
		Assert.equals("long", MuseHost.resolveFlat("orders", "long"));
		Assert.equals("orders_pending", MuseHost.resolveFlat("orders", "pending"));
		Assert.equals("fund_of", MuseHost.resolveFlat("fund", "of"));
		Assert.equals("close_of", MuseHost.resolveFlat("data", "close_of"));
		Assert.equals("portfolio_equity", MuseHost.resolveFlat("portfolio", "equity"));
		Assert.equals("plot", MuseHost.resolveFlat("chart", "plot"));
		Assert.equals("bag_equal", MuseHost.resolveFlat("bags", "equal"));
		Assert.isNull(MuseHost.resolveFlat("orders", "nope"));
		Assert.isNull(MuseHost.resolveFlat("typo", "long"));
		Assert.isNull(MuseHost.resolveFlat("math", "abs"));
		Assert.equals("Math", MuseHost.resolveObjectReceiver("math"));
		Assert.equals("params", MuseHost.resolveObjectReceiver("params"));
		Assert.equals("ta", MuseHost.resolveObjectReceiver("ta"));
	}

	public function testMuseOrdersLongMatchesFlatInterp() {
		var flatSrc = '
			@strategy("flat-long")
			@on(bar) { if (close > open) long(); }
		';
		var museSrc = '
			@strategy("muse-long")
			@on(bar) { if (close > open) muse.orders.long(); }
		';
		var bars = risingBars(40);
		var flatH = new HarnessContext();
		var museH = new HarnessContext();
		var flatR = new MuseInterp(flatH).runBacktest(new MuseParser().parse(flatSrc), new BarFeed(bars.copy()));
		var museR = new MuseInterp(museH).runBacktest(new MuseParser().parse(museSrc), new BarFeed(bars.copy()));
		Assert.equals(flatR.trades, museR.trades);
		Assert.floatEquals(flatR.finalEquity, museR.finalEquity);
		Assert.isTrue(flatR.trades > 0);
	}

	public function testMuseHostLowerRewritesToFlatCalls() {
		var src = '
			strategy S {
			  onBar {
			    muse.orders.long()
			    muse.chart.plot(close, "c")
			    muse.fund.of("AAA", "revenue")
			    muse.bags.equal(["AAA"])
			    muse.math.abs(-1)
			    muse.params.get("fast")
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("long(") >= 0, printed);
		Assert.isTrue(printed.indexOf("plot(") >= 0, printed);
		Assert.isTrue(printed.indexOf("fund_of(") >= 0, printed);
		Assert.isTrue(printed.indexOf("bag_equal(") >= 0, printed);
		Assert.isTrue(printed.indexOf("Math.abs(") >= 0 || printed.indexOf("Math . abs") >= 0
			|| printed.indexOf(".abs(") >= 0, printed);
		Assert.isTrue(printed.indexOf("params.get(") >= 0 || printed.indexOf(".get(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.orders") < 0, printed);
		Assert.isTrue(printed.indexOf("muse.chart") < 0, printed);
		Assert.isTrue(printed.indexOf("muse.fund") < 0, printed);
		Assert.isTrue(printed.indexOf("muse.bags") < 0, printed);
		Assert.isTrue(printed.indexOf("muse.math") < 0, printed);
	}

	public function testStratThisOrdersLowersToFlat() {
		var src = 'class H extends muse.Strat {\n'
			+ '  function onBar() { when close > open: this.orders.long() }\n'
			+ '}';
		var prog = ClassStrategyLower.expand(new MuseParser().parse(src));
		var text = "";
		for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body) if (n == "H"):
				text = new MusePrinter().printDecl(StrategyDecl(n, body));
			default:
		}
		Assert.isTrue(text.indexOf("long(") >= 0, text);
		Assert.isTrue(text.indexOf("this.orders") < 0, text);
		Assert.isTrue(text.indexOf("muse.orders") < 0, text);
	}

	public function testStratThisMathLowersToMath() {
		var src = 'class H extends muse.Strat {\n'
			+ '  function onBar() { when this.math.abs(close - open) > 1: long() }\n'
			+ '}';
		var prog = ClassStrategyLower.expand(new MuseParser().parse(src));
		var text = "";
		for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body) if (n == "H"):
				text = new MusePrinter().printDecl(StrategyDecl(n, body));
			default:
		}
		Assert.isTrue(text.indexOf("Math.abs(") >= 0 || text.indexOf(".abs(") >= 0, text);
		Assert.isTrue(text.indexOf("this.math") < 0, text);
	}

	public function testMuseMathInterp() {
		var src = '
			@strategy("muse-math")
			@on(bar) {
				if (muse.math.abs(close - open) >= 0) long(muse.math.min(1, 2));
			}
		';
		var bars = risingBars(20);
		var h = new HarnessContext();
		var r = new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testMuseOrdersInterpJsParity() {
		var source = '
			@strategy("muse-js-parity")
			@on(bar) {
				if (close > open) muse.orders.long();
				if (muse.orders.position() > 0 && close < open) muse.orders.flat();
			}
		';
		var bars = risingBars(80);
		var interpHarness = new HarnessContext();
		var interpResult = new MuseInterp(interpHarness).runBacktest(
			new MuseParser().parse(source), new BarFeed(bars.copy()));

		#if js
		var jsHarness = new HarnessContext();
		jsHarness.feed = new BarFeed(bars.copy());
		var ex = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "js", strict: false });
		Assert.equals("js", ex.backend);
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
		Assert.isTrue(interpResult.trades > 0);
	}

	public function testMuseOrdersWasmTier() {
		var source = '
			@strategy("muse-wasm")
			@on(bar) {
				if (close > open) muse.orders.long();
				muse.chart.plot(close, "c");
				if (muse.orders.position() > 0 && close < open) muse.orders.flat();
			}
		';
		var bars = risingBars(80);
		TradeBuiltins.resetCrossState();
		var interpH = new HarnessContext();
		var interpR = new MuseInterp(interpH).runBacktest(
			new MuseParser().parse(source), new BarFeed(bars.copy()));

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var prog = new MuseParser().parse(source);
			var wat = StrategyWasmBackend.emitWat(prog);
			Assert.notNull(wat);
			Assert.isTrue(wat.indexOf("call $long") >= 0 || wat.indexOf("$long") >= 0, wat);
			Assert.isTrue(wat.indexOf("muse.") < 0, wat);
			Assert.isTrue(wat.indexOf("call $host_eval") < 0, "expected fully native orders/chart; got escapes:\n" + wat);

			TradeBuiltins.resetCrossState();
			var wasmH = new HarnessContext();
			Reflect.setField(wasmH, "feed", new BarFeed(bars.copy()));
			var ex = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "wasm", strict: false });
			Assert.equals("wasm", ex.backend);
			var wasmR = ex.fn(wasmH);
			Assert.equals(interpR.trades, wasmR.trades);
			Assert.floatEquals(interpR.finalEquity, wasmR.finalEquity);
		}
		#end
		Assert.isTrue(interpR.trades > 0);
	}

	public function testMuseFundOfPanel() {
		var bySym = new Map<String, Array<Bar>>();
		var aaa:Array<Bar> = [];
		var bbb:Array<Bar> = [];
		for (i in 0...8) {
			var aData = i >= 2 ? ["revenue" => 1000.0 + i] : null;
			aaa.push(cast {
				open: 10.0 + i, high: 11.0 + i, low: 9.0 + i, close: 10.5 + i,
				volume: 100.0, time: (i : Float), index: i, data: aData
			});
			bbb.push(cast {
				open: 10.0 + i, high: 11.0 + i, low: 9.0 + i, close: 10.5 + i,
				volume: 100.0, time: (i : Float), index: i, data: null
			});
		}
		bySym.set("AAA", aaa);
		bySym.set("BBB", bbb);
		var panel = PanelFeed.fromSymbolBars(bySym);
		var src = '
strategy FundHost {
  onBar {
    when muse.data.sym_available("AAA") && !na(muse.fund.of("AAA", "revenue"))
      && muse.portfolio.pos("AAA") == 0: muse.portfolio.buy("AAA", 1)
  }
}
';
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var result = new MuseInterp(harness).runPanelBacktest(new MuseParser().parse(src), panel);
		Assert.isTrue(result.trades > 0);
		Assert.isTrue(harness.portfolio.positionOf("AAA") > 0);
	}

	public function testPaletteFieldsStayOhlcvCore() {
		Assert.same(["open", "high", "low", "close", "volume"], Palette.FIELDS);
		Assert.isTrue(Palette.AUX_FIELDS.indexOf("revenue") >= 0);
		Assert.isTrue(Palette.FIELDS.indexOf("revenue") < 0);
	}

	public function testFieldsForGatesAuxByTapePresence() {
		Assert.same(Palette.FIELDS, Palette.fieldsFor(null));
		Assert.same(Palette.FIELDS, Palette.fieldsFor([]));
		var gated = Palette.fieldsFor(["revenue", "noise_not_in_catalog", "pe"]);
		Assert.isTrue(gated.indexOf("close") >= 0);
		Assert.isTrue(gated.indexOf("revenue") >= 0);
		Assert.isTrue(gated.indexOf("pe") >= 0);
		Assert.isTrue(gated.indexOf("noise_not_in_catalog") < 0);
		Assert.isTrue(gated.indexOf("sentiment") < 0);
	}

	public function testExpandEmitsFundAuxSeriesAccess() {
		var g = genome(BCmp(">", KSeries(SPrice("revenue")), KConst(1000.0)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("revenue") >= 0, src);
		Assert.isTrue(src.indexOf("muse.") < 0, src);
		Assert.isTrue(src.indexOf("fund_of") < 0, src);
		Assert.isTrue(src.indexOf("long(") >= 0, src);
	}

	public function testExpandDoesNotEmitMuseHost() {
		var g = genome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("muse.") < 0, src);
		Assert.isTrue(src.indexOf("fund_of") < 0, src);
		Assert.isTrue(src.indexOf("long(") >= 0, src);
	}

	public function testVariationGrowsAuxWhenConfigured() {
		var bars = barsWithRevenue(40);
		var v = new Variation(7);
		v.configureForTape(bars);
		var pool = Palette.fieldsFor(Palette.auxPresentOn(bars));
		Assert.isTrue(pool.indexOf("revenue") >= 0);
		Assert.isTrue(pool.indexOf("pe") >= 0);
		var sawAux = false;
		for (_ in 0...120) {
			var g = v.randomGenome(2);
			var src = Expand.expand(g);
			if (src.indexOf("revenue") >= 0 || src.indexOf('"pe"') >= 0
					|| src.indexOf(" pe ") >= 0 || src.indexOf("(pe ") >= 0) {
				sawAux = true;
				break;
			}
		}
		Assert.isTrue(sawAux, "expected fund/aux field in some grown genome");
	}

	public function testVariationOhlcvOnlyWithoutTapeAux() {
		var v = new Variation(11);
		v.configureForTape(risingBars(40));
		for (_ in 0...40) {
			var g = v.randomGenome(2);
			var src = Expand.expand(g);
			// Token-aware: substring "pe" also matches inside "open".
			Assert.isTrue(src.indexOf("revenue") < 0, src);
			Assert.isTrue(src.indexOf('"pe"') < 0, src);
			Assert.isTrue(src.indexOf("(pe ") < 0 && src.indexOf(" pe ") < 0 && src.indexOf(" pe)") < 0, src);
		}
	}

	public function testEvoFitnessUnchangedForOhlcvGenome() {
		var g = genome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		var bars = BarFeed.synthetic(200, 42).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok, r.error);
		Assert.isTrue(r.trades >= 0);
	}

	public function testFitnessAndNmaHandleAuxColumns() {
		var bars = barsWithRevenue(120);
		var g = genome(BCmp(">", KSeries(SPrice("revenue")), KConst(1005.0)));
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok, r.error);

		var nma = NmaFitness.evaluate(g, bars);
		Assert.isTrue(nma.ok, nma.error);
		// OHLCV-only genome still works on the same tape.
		var ohlcv = genome(BCross("over", SPrice("close"), SInd("sma", "close", 5, null)));
		var r2 = Fitness.evaluate(ohlcv, bars, "js", false);
		Assert.isTrue(r2.ok, r2.error);
		var nma2 = NmaFitness.evaluate(ohlcv, bars);
		Assert.isTrue(nma2.ok, nma2.error);
	}

	public function testAuxSeriesInterpCausal() {
		var bars = barsWithRevenue(30);
		var src = '
			@strategy("aux-rev")
			@on(bar) {
				if (!na(revenue) && revenue > 1005) long();
				if (position() > 0 && revenue < 1008) flat();
			}
		';
		var h = new HarnessContext();
		var r = new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	/** Single-symbol Bar.data aux lowers natively (feature tape), no host_eval. */
	public function testAuxSeriesWasmNativeParity() {
		var source = '
			@strategy("aux-wasm")
			@on(bar) {
				if (!na(revenue) && revenue > 1005) long();
				if (position() > 0 && revenue < 1008) flat();
			}
		';
		var bars = barsWithRevenue(40);
		TradeBuiltins.resetCrossState();
		var interpH = new HarnessContext();
		var interpR = new MuseInterp(interpH).runBacktest(
			new MuseParser().parse(source), new BarFeed(bars.copy()));
		Assert.isTrue(interpR.trades > 0);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var prog = new MuseParser().parse(source);
			var emitted = StrategyWasmBackend.emitOnBar(prog);
			Assert.notNull(emitted);
			Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0, emitted.wat);
			Assert.isTrue(emitted.wat.indexOf("lookback_ohlcv") >= 0
				|| emitted.wat.indexOf("feature_at") >= 0, emitted.wat);
			Assert.isTrue(StrategyWasmBackend.featureSlotCount(emitted.strings) >= 1);
			Assert.isTrue(StrategyWasmBackend.featureKeysFromStrings(emitted.strings).indexOf("revenue") >= 0);

			TradeBuiltins.resetCrossState();
			var wasmH = new HarnessContext();
			Reflect.setField(wasmH, "feed", new BarFeed(bars.copy()));
			var ex = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "wasm", strict: false });
			Assert.equals("wasm", ex.backend);
			var wasmR = ex.fn(wasmH);
			Assert.equals(interpR.trades, wasmR.trades);
			Assert.floatEquals(interpR.finalEquity, wasmR.finalEquity);
		}
		#end
	}

	/** Aux lookback + sma on Bar.data stay native WASM. */
	public function testAuxLookbackSmaWasmNative() {
		var source = '
			@strategy("aux-sma")
			@on(bar) {
				if (!na(sma(revenue, 3)) && sma(revenue, 3) > 1004 && revenue[1] > 1003) long();
			}
		';
		var bars = barsWithRevenue(50);
		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
			Assert.notNull(wat);
			Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
			Assert.isTrue(wat.indexOf("call $sma") >= 0, wat);
			Assert.isTrue(wat.indexOf("lookback_ohlcv") >= 0, wat);

			TradeBuiltins.resetCrossState();
			var interpR = new MuseInterp(new HarnessContext()).runBacktest(
				new MuseParser().parse(source), new BarFeed(bars.copy()));
			TradeBuiltins.resetCrossState();
			var wasmH = new HarnessContext();
			Reflect.setField(wasmH, "feed", new BarFeed(bars.copy()));
			var wasmR = MuseCompiler.compileEx(new MuseParser().parse(source), { target: "wasm", strict: false }).fn(wasmH);
			Assert.equals(interpR.trades, wasmR.trades);
		}
		#end
	}

	/**
	 * Panel fund_of / close_of / sym_available lower onto field@SYM feature slots (v1).
	 * buy may still host_eval; bags stay on the escape list.
	 */
	public function testPanelFundOfNativeFeatureSlots() {
		var source = '
			@strategy("panel-fund")
			@on(bar) {
				if (sym_available("AAA") && !na(fund_of("AAA", "revenue"))) buy("AAA", 1);
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(source));
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		var keys = StrategyWasmBackend.featureKeysFromStrings(emitted.strings);
		Assert.isTrue(keys.indexOf("revenue@AAA") >= 0, keys.join(","));
		Assert.isTrue(keys.indexOf("close@AAA") >= 0, keys.join(","));
		Assert.isTrue(emitted.wat.indexOf("call $lookback_ohlcv") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $buy") >= 0, emitted.wat);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") < 0, "panel reads+buy should be native/ABI");
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_equal") >= 0);
	}

	public function testFeatureTapesFromBarData() {
		var bars = barsWithRevenue(5);
		var strings = [
			StrategyWasmEmitter.FEATURE_SLOT_PREFIX + "revenue",
			StrategyWasmEmitter.FEATURE_SLOT_PREFIX + "pe"
		];
		var tapes = StrategyWasmBackend.featureTapesFromCtx(null, strings, bars);
		Assert.equals(2, tapes.length);
		Assert.isTrue(Math.isNaN(tapes[0][0]));
		Assert.isTrue(Math.isNaN(tapes[0][1]));
		Assert.floatEquals(1002.0, tapes[0][2]);
		Assert.floatEquals(12.2, tapes[1][2], 1e-9);
	}
}
