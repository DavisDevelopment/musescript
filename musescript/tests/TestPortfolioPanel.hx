package musescript.tests;

import musescript.builtins.PortfolioBuiltins;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;
import musescript.harness.PortfolioSim;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import utest.Assert;
import utest.Test;

class TestPortfolioPanel extends Test {
	public function testPortfolioSimRebalanceEqual() {
		var book = new PortfolioSim(100000);
		var prices = new Map<String, Float>();
		prices.set("AAA", 100);
		prices.set("BBB", 50);
		prices.set("CCC", 25);
		book.rebalanceEqual(["AAA", "BBB"], prices, 0);
		Assert.equals(2, book.holdings().length);
		Assert.isTrue(book.positionOf("AAA") > 0);
		Assert.isTrue(book.positionOf("BBB") > 0);
		Assert.equals(0.0, book.positionOf("CCC"));
		book.rebalanceEqual(["CCC"], prices, 1);
		Assert.equals(1, book.holdings().length);
		Assert.isTrue(book.positionOf("CCC") > 0);
		Assert.equals(0.0, book.positionOf("AAA"));
	}

	public function testScanTopBottom() {
		var scores = new Map<String, Dynamic>();
		scores.set("A", 1.0);
		scores.set("B", 3.0);
		scores.set("C", 2.0);
		Assert.same(["B", "C"], PortfolioBuiltins.rankPick(scores, 2, false));
		Assert.same(["A", "C"], PortfolioBuiltins.rankPick(scores, 2, true));
	}

	public function testPanelSyntheticShape() {
		var panel = PanelFeed.synthetic(5, 40, 3);
		Assert.equals(5, panel.symbols.length);
		Assert.equals(40, panel.length());
		Assert.isTrue(panel.pricesAt(10).exists(panel.symbols[0]));
	}

	public function testMomScannerInterp() {
		var src = '
strategy MomScan {
  param topN = 3
  param look = 5
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    picks = scan_top(scores, topN)
    rebalance_equal(picks)
  }
}
';
		var prog = new MuseParser().parse(src, "mom-scan.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(8, 80, 11);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.isTrue(result.trades > 0);
		Assert.isTrue(result.finalEquity > 0);
		Assert.isTrue(harness.portfolio.equity.length == 80);
		Assert.equals(8, harness.panelSymbols.length);
	}

	public function testMomScannerCompiledJs() {
		#if js
		var src = '
strategy MomScanJs {
  param topN = 2
  param look = 4
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    rebalance_equal(scan_top(scores, topN))
  }
}
';
		var prog = new MuseParser().parse(src, "mom-scan-js.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(6, 60, 19);
		harness.panel = panel;
		var fn = MuseCompiler.compile(prog, { target: "js" });
		var result = fn(harness);
		Assert.isTrue(result.trades >= 0);
		Assert.isTrue(result.finalEquity > 0);
		Assert.equals(60, harness.portfolio.equity.length);
		#end
		Assert.isTrue(true);
	}

	public function testBuiltinSigsPresent() {
		Assert.notNull(musescript.types.BuiltinSigs.get("symbols"));
		Assert.notNull(musescript.types.BuiltinSigs.get("scan_top"));
		Assert.notNull(musescript.types.BuiltinSigs.get("rebalance_equal"));
		Assert.notNull(musescript.types.BuiltinSigs.get("buy"));
		Assert.notNull(musescript.types.BuiltinSigs.get("mom_of"));
		Assert.notNull(musescript.types.BuiltinSigs.get("fund_of"));
	}

	/**
	 * Build a 2-symbol, 6-bar panel where AAA carries a "revenue" aux field
	 * that is only known (non-NaN) from bar index 3 onward (its synthetic
	 * "filing date"), and BBB never reports it at all. This is the PIT leak
	 * firewall for the panel path: fund_of must read NaN strictly before the
	 * fact's first bar and the real value from that bar on, never early and
	 * never stale-into-the-past.
	 */
	static function panelWithFiledFundamental():PanelFeed {
		var bySym = new Map<String, Array<musescript.harness.Bar>>();
		var aaa:Array<musescript.harness.Bar> = [];
		var bbb:Array<musescript.harness.Bar> = [];
		for (i in 0...6) {
			var base:Dynamic = { open: 10.0 + i, high: 11.0 + i, low: 9.0 + i,
				close: 10.5 + i, volume: 100.0, time: (i : Float), index: i };
			// AAA's "revenue" fact is filed at bar 3; the loader forward-fills
			// it from there on and leaves it NaN before (this is what a PIT
			// join looks like once it reaches PanelFeed — the causal-push
			// discipline below is what stops bar t from seeing bar t+1's value).
			var aData = i >= 3 ? [ "revenue" => 1000.0 + i ] : null;
			aaa.push(cast { open: base.open, high: base.high, low: base.low,
				close: base.close, volume: base.volume, time: base.time, index: base.index, data: aData });
			bbb.push(cast { open: base.open, high: base.high, low: base.low,
				close: base.close, volume: base.volume, time: base.time, index: base.index, data: null });
		}
		bySym.set("AAA", aaa);
		bySym.set("BBB", bbb);
		return PanelFeed.fromSymbolBars(bySym);
	}

	public function testFundOfInvisibleBeforeFilingVisibleAfter() {
		var panel = panelWithFiledFundamental();
		Assert.isTrue(panel.auxFieldNames.indexOf("revenue") >= 0);

		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var seenBefore:Array<Float> = [];
		var seenAfter:Array<Float> = [];
		var seenBbb:Array<Float> = [];
		var t = 0;
		musescript.runtime.IterDriver.each(panel.asBarFeed(), function(item) {
			var bar:musescript.harness.Bar = cast item;
			harness.currentBar = bar;
			harness.pushSeries("open", bar.open);
			harness.pushSeries("high", bar.high);
			harness.pushSeries("low", bar.low);
			harness.pushSeries("close", bar.close);
			harness.pushSeries("volume", bar.volume);
			PortfolioBuiltins.observePanel(harness, panel, t);
			var v = harness.seriesLookback(PortfolioBuiltins.seriesKey("revenue", "AAA"), 0);
			var vb = harness.seriesLookback(PortfolioBuiltins.seriesKey("revenue", "BBB"), 0);
			if (t < 3) seenBefore.push(v) else seenAfter.push(v);
			seenBbb.push(vb);
			harness.portfolio.mark(harness.panelPrices);
			t++;
		});

		// Strictly unavailable before the filing bar.
		for (v in seenBefore) Assert.isTrue(Math.isNaN(v));
		// Visible with the correct value from the filing bar on (no stale
		// carry-forward of a wrong constant, no early leak of the future value).
		Assert.equals(3, seenAfter.length);
		Assert.floatEquals(1003.0, seenAfter[0]);
		Assert.floatEquals(1004.0, seenAfter[1]);
		Assert.floatEquals(1005.0, seenAfter[2]);
		// A symbol that never files the fact stays NaN for the whole run.
		for (v in seenBbb) Assert.isTrue(Math.isNaN(v));
	}

	public function testFundOfBuiltinReadsCurrentBarOnly() {
		// End-to-end through the installed builtin (not just seriesLookback):
		// a strategy reading fund_of("AAA","revenue") at each bar must trade
		// the causal value only — proven by gating a single entry on the
		// fact becoming available, mirroring TestAuxData's single-symbol test.
		var panel = panelWithFiledFundamental();
		var src = '
strategy FundGate {
  onBar {
    when sym_available("AAA") && !na(fund_of("AAA", "revenue")) && pos("AAA") == 0: buy("AAA", 1)
  }
}
';
		var prog = new MuseParser().parse(src, "fund-gate.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		// Can only ever buy once revenue is known (bar 3+); a lookahead bug
		// (preloaded aux) would let this fire from bar 0.
		Assert.equals(1, result.trades);
		Assert.equals(3, harness.portfolio.entryBars.get("AAA"));
	}

	/**
	 * `toStringArray` (feeding `rebalance_equal`/`target_weight`/bag builtins) previously only
	 * recognized a plain Array — a lazy MuseIter (what `filter()`/`map()`/`take()`/… actually
	 * return) fell through to its bare-scalar fallback and got silently stringified as ONE bogus
	 * "symbol" (the iterator object). Regression: `filter()`'s result must survive intact.
	 */
	public function testToStringArrayMaterializesLazyIter() {
		var arr:Array<Dynamic> = ["AAA", "BBB", "CCC"];
		var lazy = musescript.runtime.IterDriver.filter(
			musescript.runtime.MuseIters.from(arr), function(v) return v != "BBB");
		Assert.same(["AAA", "CCC"], PortfolioBuiltins.toStringArray(lazy));
		// A bare scalar still wraps as a one-element list (unchanged prior behavior).
		Assert.same(["AAA"], PortfolioBuiltins.toStringArray("AAA"));
		// A plain Array still passes through element-wise (unchanged prior behavior).
		Assert.same(["AAA", "BBB"], PortfolioBuiltins.toStringArray(["AAA", "BBB"]));
	}

	/** End-to-end: `rebalance_equal(filter(picks, pred))` must actually trade, not silently no-op. */
	public function testRebalanceEqualWithFilteredPicks() {
		var panel = PanelFeed.synthetic(5, 30, 7);
		var src = '
strategy FilteredRebalance {
  onBar {
    picks = filter(symbols(), s => true)
    rebalance_equal(picks)
  }
}
';
		var prog = new MuseParser().parse(src, "filtered-rebalance.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.isTrue(result.trades > 0, "filter()'s output must reach rebalance_equal intact");
		Assert.equals(5, harness.portfolio.holdings().length);
	}

	/** Tiny 2-symbol panel with controllable OHLC for pending-book tests. */
	static function panelTwoSymPending():PanelFeed {
		var bySym = new Map<String, Array<musescript.harness.Bar>>();
		var aaa:Array<musescript.harness.Bar> = [];
		var bbb:Array<musescript.harness.Bar> = [];
		// bar0: place bar; bar1: AAA dips to fill limit@95; BBB stays above; bar2+: quiet
		var rows:Array<{o:Float, h:Float, l:Float, c:Float}> = [
			{ o: 100, h: 101, l: 99, c: 100 },
			{ o: 100, h: 101, l: 94, c: 96 },
			{ o: 96, h: 97, l: 95, c: 96 },
			{ o: 96, h: 98, l: 95, c: 97 },
			{ o: 97, h: 99, l: 96, c: 98 },
			{ o: 98, h: 100, l: 97, c: 99 }
		];
		for (i in 0...rows.length) {
			var r = rows[i];
			aaa.push({
				open: r.o, high: r.h, low: r.l, close: r.c, volume: 1000,
				time: (i : Float), index: i
			});
			// BBB never touches 95 — stays elevated so its pending limit stays working
			bbb.push({
				open: r.o + 20, high: r.h + 20, low: r.l + 20, close: r.c + 20, volume: 1000,
				time: (i : Float), index: i
			});
		}
		bySym.set("AAA", aaa);
		bySym.set("BBB", bbb);
		return PanelFeed.fromSymbolBars(bySym);
	}

	public function testPanelPendingLimitFillMultiSym() {
		var sim = new PortfolioSim(100000);
		sim.submit("long", "AAA", { type: "limit", px: 95.0, qty: 10.0 }, 100.0, 0);
		sim.submit("long", "BBB", { type: "limit", px: 95.0, qty: 10.0 }, 120.0, 0);
		Assert.equals(2, sim.pendingCount());
		Assert.equals(1, sim.pendingCount("AAA"));
		Assert.equals(0.0, sim.positionOf("AAA"));

		var o1 = new Map<String, Float>();
		o1.set("AAA", 100.0); o1.set("BBB", 120.0);
		var h1 = new Map<String, Float>();
		h1.set("AAA", 101.0); h1.set("BBB", 121.0);
		var l1 = new Map<String, Float>();
		l1.set("AAA", 94.0); l1.set("BBB", 114.0);
		sim.beginBar(o1, h1, l1, 1);
		Assert.floatEquals(10.0, sim.positionOf("AAA"));
		Assert.equals(0.0, sim.positionOf("BBB")); // BBB never touched 95
		Assert.equals(0, sim.pendingCount("AAA"));
		Assert.equals(1, sim.pendingCount("BBB"));
		Assert.floatEquals(95.0, sim.fills[0].price);
		Assert.equals("AAA", sim.fills[0].symbol);
	}

	public function testPanelPendingCancelLeavesOtherSym() {
		var sim = new PortfolioSim(100000);
		sim.submit("long", "AAA", { type: "limit", px: 95.0, qty: 5.0 }, 100.0, 0);
		sim.submit("long", "BBB", { type: "limit", px: 95.0, qty: 5.0 }, 100.0, 0);
		Assert.equals(1, sim.cancelAll("AAA"));
		Assert.equals(0, sim.pendingCount("AAA"));
		Assert.equals(1, sim.pendingCount("BBB"));
		Assert.equals(1, sim.cancelAll()); // cancels remaining
		Assert.equals(0, sim.pendingCount());
	}

	public function testPanelOcoPerSymbolIndependentGroups() {
		var sim = new PortfolioSim(100000);
		sim.buy("AAA", 100.0, 10.0, 0);
		sim.submit("flat", "AAA", { type: "stop", px: 90.0, groupId: 1, onFill: "cancel_group" }, 100.0, 0);
		sim.submit("flat", "AAA", { type: "limit", px: 110.0, groupId: 1, onFill: "cancel_group" }, 100.0, 0);
		// Distinct groupId → BBB OCO must survive AAA's fill
		sim.buy("BBB", 100.0, 10.0, 0);
		sim.submit("flat", "BBB", { type: "stop", px: 90.0, groupId: 2, onFill: "cancel_group" }, 100.0, 0);
		sim.submit("flat", "BBB", { type: "limit", px: 110.0, groupId: 2, onFill: "cancel_group" }, 100.0, 0);
		Assert.equals(4, sim.pendingCount());

		var o = new Map<String, Float>();
		o.set("AAA", 100.0); o.set("BBB", 100.0);
		var h = new Map<String, Float>();
		h.set("AAA", 112.0); h.set("BBB", 101.0);
		var l = new Map<String, Float>();
		l.set("AAA", 88.0); l.set("BBB", 99.0);
		sim.beginBar(o, h, l, 1);
		Assert.equals(0.0, sim.positionOf("AAA"));
		Assert.floatEquals(10.0, sim.positionOf("BBB"));
		Assert.equals(0, sim.pendingCount("AAA"));
		Assert.equals(2, sim.pendingCount("BBB")); // BBB group untouched
	}

	/** Shared groupId is portfolio-global: AAA fill cancels BBB siblings. */
	public function testPanelOcoCrossSymbolCancelRest() {
		var sim = new PortfolioSim(100000);
		var gid = sim.allocGroupId();
		sim.buy("AAA", 100.0, 10.0, 0);
		sim.submit("flat", "AAA", { type: "stop", px: 90.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		sim.submit("flat", "AAA", { type: "limit", px: 110.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		sim.buy("BBB", 100.0, 10.0, 0);
		sim.submit("flat", "BBB", { type: "stop", px: 90.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		sim.submit("flat", "BBB", { type: "limit", px: 110.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		Assert.equals(4, sim.pendingCount());

		var o = new Map<String, Float>();
		o.set("AAA", 100.0); o.set("BBB", 100.0);
		var h = new Map<String, Float>();
		// AAA stop touches (and would TP); BBB stays quiet — only AAA would fill locally
		h.set("AAA", 112.0); h.set("BBB", 101.0);
		var l = new Map<String, Float>();
		l.set("AAA", 88.0); l.set("BBB", 99.0);
		sim.beginBar(o, h, l, 1);
		Assert.equals(0.0, sim.positionOf("AAA"));
		Assert.floatEquals(10.0, sim.positionOf("BBB")); // BBB never flat-filled
		Assert.equals(0, sim.pendingCount("AAA"));
		Assert.equals(0, sim.pendingCount("BBB")); // cancelled by AAA's cancel_group fan-out
		Assert.equals(0, sim.cancelGroup(gid)); // already cleared
	}

	/** Panel bracket sugar: entry + OCO stop/TP on one symbol via submit. */
	public function testPanelBracketSugarExpandAndFill() {
		var sim = new PortfolioSim(100000);
		sim.submit("long", "AAA", {
			qty: 10.0,
			bracket: { stop: { px: 90.0 }, limit: { px: 110.0 }, link: "oco" }
		}, 100.0, 0);
		Assert.equals(3, sim.pendingCount("AAA"));
		var pend = sim.bookOf("AAA").pending;
		Assert.equals("long", pend[0].kind);
		Assert.equals(null, pend[0].groupId);
		Assert.equals(pend[1].groupId, pend[2].groupId);
		Assert.equals("cancel_group", pend[1].onFill);

		var o = new Map<String, Float>();
		o.set("AAA", 100.0);
		var h = new Map<String, Float>();
		h.set("AAA", 112.0);
		var l = new Map<String, Float>();
		l.set("AAA", 88.0);
		sim.beginBar(o, h, l, 1);
		Assert.equals(0.0, sim.positionOf("AAA"));
		Assert.equals(0, sim.pendingCount("AAA"));
		Assert.equals(2, sim.fills.length); // entry + stop
		Assert.equals("long", sim.fills[0].kind);
		Assert.equals("flat", sim.fills[1].kind);
		Assert.floatEquals(90.0, sim.fills[1].price);
	}

	/** Cross-symbol: two brackets sharing one allocGroupId via explicit exit specs. */
	public function testPanelBracketCrossSymSharedExitGroup() {
		var sim = new PortfolioSim(100000);
		var gid = sim.allocGroupId();
		sim.submit("long", "AAA", { type: "market", qty: 5.0 }, 100.0, 0);
		sim.submit("long", "BBB", { type: "market", qty: 5.0 }, 100.0, 0);
		sim.submit("flat", "AAA", { type: "stop", px: 90.0, qty: 5.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		sim.submit("flat", "BBB", { type: "stop", px: 90.0, qty: 5.0, groupId: gid, onFill: "cancel_group" }, 100.0, 0);
		Assert.equals(4, sim.pendingCount());

		var o = new Map<String, Float>();
		o.set("AAA", 100.0); o.set("BBB", 100.0);
		var h = new Map<String, Float>();
		h.set("AAA", 101.0); h.set("BBB", 101.0);
		var l = new Map<String, Float>();
		l.set("AAA", 88.0); l.set("BBB", 99.0); // only AAA stop touches
		sim.beginBar(o, h, l, 1);
		Assert.equals(0.0, sim.positionOf("AAA"));
		Assert.floatEquals(5.0, sim.positionOf("BBB"));
		Assert.equals(0, sim.pendingCount());
	}

	public function testPanelBracketThroughInterp() {
		var src = '
strategy PanelBracket {
  onBar {
    when bar_index == 0:
      portfolio_long("AAA", {
        qty: 10.0,
        bracket: { stop: { px: 90.0 }, limit: { px: 110.0 }, link: "oco" }
      })
  }
}
';
		var prog = new MuseParser().parse(src, "panel-bracket.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var bySym = new Map<String, Array<musescript.harness.Bar>>();
		var bars:Array<musescript.harness.Bar> = [
			{ open: 100, high: 101, low: 99, close: 100, volume: 1000, time: 0, index: 0 },
			{ open: 100, high: 112, low: 88, close: 100, volume: 1000, time: 1, index: 1 },
			{ open: 100, high: 101, low: 99, close: 100, volume: 1000, time: 2, index: 2 }
		];
		bySym.set("AAA", bars);
		bySym.set("BBB", bars.copy());
		var panel = PanelFeed.fromSymbolBars(bySym);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.equals(0.0, harness.portfolio.positionOf("AAA"));
		Assert.equals(0, harness.portfolio.pendingCount());
		Assert.equals(2, result.trades);
		Assert.floatEquals(90.0, harness.portfolio.fills[1].price);
	}

	/** Object/bracket specs stay on PANEL_HOST_ESCAPE → host_eval (HostABI is qty-only). */
	public function testPanelBracketWasmHostEval() {
		var src = '
strategy PanelBracketWasm {
  onBar {
    when bar_index == 0:
      portfolio_long("AAA", {
        qty: 10.0,
        bracket: { stop: { px: 90.0 }, limit: { px: 110.0 }, link: "oco" }
      })
  }
}
';
		var prog = new MuseParser().parse(src, "panel-bracket-wasm.ms");
		var emitted = musescript.compile.StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(StringTools.contains(emitted.wat, "host_eval"),
			"complex portfolio_long specs must host_eval");
		Assert.isTrue(
			musescript.compile.StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("portfolio_long") >= 0);
	}

	public function testPanelLegacyBuyRebalanceStillImmediate() {
		var sim = new PortfolioSim(100000);
		var prices = new Map<String, Float>();
		prices.set("AAA", 100.0);
		prices.set("BBB", 50.0);
		sim.buy("AAA", 100.0, 10.0, 0);
		Assert.equals(0, sim.pendingCount());
		Assert.floatEquals(10.0, sim.positionOf("AAA"));
		sim.rebalanceEqual(["AAA", "BBB"], prices, 1);
		Assert.equals(0, sim.pendingCount());
		Assert.isTrue(sim.positionOf("AAA") > 0);
		Assert.isTrue(sim.positionOf("BBB") > 0);
	}

	public function testPanelPendingNoSameBarFill() {
		var sim = new PortfolioSim(100000);
		sim.submit("long", "AAA", { type: "market", qty: 5.0 }, 100.0, 5);
		var o = new Map<String, Float>();
		o.set("AAA", 100.0);
		sim.beginBar(o, o, o, 5);
		Assert.equals(0.0, sim.positionOf("AAA"));
		Assert.equals(1, sim.pendingCount("AAA"));
		sim.beginBar(o, o, o, 6);
		Assert.floatEquals(5.0, sim.positionOf("AAA"));
	}

	public function testPanelPendingThroughInterp() {
		var src = '
strategy PanelPend {
  onBar {
    when bar_index == 0: portfolio_long("AAA", { type: "limit", px: 95.0, qty: 10.0 })
    when bar_index == 0: portfolio_long("BBB", { type: "limit", px: 95.0, qty: 10.0 })
  }
}
';
		var prog = new MuseParser().parse(src, "panel-pend.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = panelTwoSymPending();
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.floatEquals(10.0, harness.portfolio.positionOf("AAA"));
		Assert.equals(0.0, harness.portfolio.positionOf("BBB"));
		Assert.equals(0, harness.portfolio.pendingCount("AAA"));
		Assert.equals(1, harness.portfolio.pendingCount("BBB"));
		Assert.isTrue(result.trades >= 1);
	}

	public function testPanelPendingCancelThroughInterp() {
		var src = '
strategy PanelPendCancel {
  onBar {
    when bar_index == 0: {
      portfolio_long("AAA", { type: "limit", px: 95.0, qty: 10.0 })
      portfolio_long("BBB", { type: "limit", px: 95.0, qty: 10.0 })
      portfolio_orders_cancel_all("AAA")
    }
  }
}
';
		var prog = new MuseParser().parse(src, "panel-pend-cancel.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		new MuseInterp(harness).runPanelBacktest(prog, panelTwoSymPending());
		Assert.equals(0.0, harness.portfolio.positionOf("AAA"));
		Assert.equals(0, harness.portfolio.pendingCount("AAA"));
		Assert.equals(1, harness.portfolio.pendingCount("BBB"));
	}

	public function testBuiltinPendingSigsPresent() {
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_long"));
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_short"));
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_flat"));
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_orders_pending"));
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_orders_cancel_all"));
	}
}
