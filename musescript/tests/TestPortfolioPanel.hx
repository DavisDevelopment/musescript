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
}
