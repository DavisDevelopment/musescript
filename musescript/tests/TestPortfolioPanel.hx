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
		Reflect.setField(harness, "panel", panel);
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
	}
}
