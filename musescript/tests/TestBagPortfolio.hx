package musescript.tests;

import musescript.builtins.BagBuiltins;
import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;
import musescript.harness.SymbolBag;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import utest.Assert;
import utest.Test;

class TestBagPortfolio extends Test {
	public function testBagAlgebra() {
		var a = BagBuiltins.bagEqual(["A", "B"], "ab");
		Assert.equals(0.5, a.weightOf("A"));
		Assert.equals("ab", a.name);
		var p = BagBuiltins.bagPair("A", "C", 1.0, "pair");
		Assert.equals(0.5, p.weightOf("A"));
		Assert.equals(-0.5, p.weightOf("C"));
		var sum = BagBuiltins.bagAdd(a, p, "sum");
		Assert.equals(1.0, sum.weightOf("A"));
		Assert.equals(0.5, sum.weightOf("B"));
		Assert.equals(-0.5, sum.weightOf("C"));
		var masked = BagBuiltins.bagMask(sum, ["A", "C"], "m");
		Assert.equals(1.0, masked.weightOf("A"));
		Assert.equals(0.0, masked.weightOf("B"));
		Assert.isFalse(masked.weights.exists("B"));
		var sub = BagBuiltins.bagSub(sum, p, null);
		Assert.equals(0.5, sub.weightOf("A"));
		Assert.equals(0.5, sub.weightOf("B"));
		Assert.isFalse(sub.weights.exists("C"));
		var norm = BagBuiltins.bagNorm(BagBuiltins.bagScale(a, 4, null), null);
		Assert.equals(0.5, norm.weightOf("A"));
	}

	public function testPortfolioApplyPair() {
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(4, 30, 5);
		musescript.builtins.PortfolioBuiltins.observePanel(harness, panel, 10);
		harness.currentBar = panel.all()[10];
		var pair = BagBuiltins.bagPair(panel.symbols[0], panel.symbols[1], 1.0, "p");
		harness.portfolio.applyBag(pair.weights, harness.panelPrices, 10, true);
		Assert.isTrue(harness.portfolio.positionOf(panel.symbols[0]) > 0);
		Assert.isTrue(harness.portfolio.positionOf(panel.symbols[1]) < 0);
		Assert.isTrue(harness.portfolio.equityAt(harness.panelPrices) > 0);
	}

	public function testBagStrategyInterp() {
		var src = '
strategy BagSleeve {
  param topN = 3
  param look = 5
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    core = bag_equal(scan_top(scores, topN), "mom")
    portfolio_apply(core)
  }
}
';
		var prog = new MuseParser().parse(src, "bag-sleeve.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(6, 50, 13);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.isTrue(result.trades > 0, "trades=" + result.trades);
		Assert.isTrue(result.finalEquity > 0);
		Assert.isTrue(SymbolBag.isBag(BagBuiltins.bagNew("x")));
	}

	public function testPortfolioAddSubMask() {
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(5, 20, 2);
		musescript.builtins.PortfolioBuiltins.observePanel(harness, panel, 8);
		harness.currentBar = panel.all()[8];
		var s0 = panel.symbols[0];
		var s1 = panel.symbols[1];
		var s2 = panel.symbols[2];
		harness.portfolio.applyBag(BagBuiltins.bagEqual([s0, s1], "ab").weights, harness.panelPrices, 8, true);
		Assert.isTrue(harness.portfolio.positionOf(s0) > 0);
		Assert.isTrue(harness.portfolio.positionOf(s1) > 0);
		// mask to only s0
		var kept = BagBuiltins.bagMask(BagBuiltins.portfolioBag(harness, ""), [s0], null);
		harness.portfolio.applyBag(kept.weights, harness.panelPrices, 8, true);
		Assert.isTrue(harness.portfolio.positionOf(s0) > 0);
		Assert.equals(0.0, harness.portfolio.positionOf(s1));
		// add s2 sleeve
		var add = BagBuiltins.bagEqual([s2], "c");
		var cur = BagBuiltins.portfolioBag(harness, "");
		var merged = BagBuiltins.bagAdd(cur, add, null);
		harness.portfolio.applyBag(merged.weights, harness.panelPrices, 8, false);
		Assert.isTrue(harness.portfolio.positionOf(s2) > 0);
	}

	public function testBuiltinSigs() {
		Assert.notNull(musescript.types.BuiltinSigs.get("bag"));
		Assert.notNull(musescript.types.BuiltinSigs.get("bag_pair"));
		Assert.notNull(musescript.types.BuiltinSigs.get("bag_computed"));
		Assert.notNull(musescript.types.BuiltinSigs.get("bag_rank_mom"));
		Assert.notNull(musescript.types.BuiltinSigs.get("bag_resolve"));
		Assert.notNull(musescript.types.BuiltinSigs.get("portfolio_apply"));
		Assert.isTrue(Type.enumEq(
			musescript.types.BuiltinSigs.get("bag").ret,
			musescript.types.MuseType.TBag
		));
	}

	public function testComputedRankMom() {
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(6, 40, 7);
		for (t in 0...26)
			musescript.builtins.PortfolioBuiltins.observePanel(harness, panel, t);
		harness.currentBar = panel.all()[25];
		var bag = BagBuiltins.bagRecipe("mom3", { op: "rank_mom", n: 3, look: 5 });
		Assert.isTrue(bag.isComputed());
		Assert.equals("computed", bag.mode);
		var snap = BagBuiltins.materialize(harness, bag);
		Assert.equals("static", snap.mode);
		Assert.equals(3, snap.size());
		Assert.isTrue(snap.size() > 0);
		harness.portfolio.applyBag(snap.weights, harness.panelPrices, 25, true);
		Assert.isTrue(harness.portfolio.holdings().length > 0);
	}

	public function testComputedGraphNeighbors() {
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(4, 20, 3);
		musescript.builtins.PortfolioBuiltins.observePanel(harness, panel, 10);
		harness.currentBar = panel.all()[10];
		var s0 = panel.symbols[0];
		var s1 = panel.symbols[1];
		var s2 = panel.symbols[2];
		var graph = {
			directed: true,
			nodes: [s0, s1, s2],
			edges: [{ from: s0, to: s1 }, { from: s0, to: s2 }]
		};
		var bag = BagBuiltins.bagRecipe("nbr", {
			op: "graph_neighbors",
			graph: graph,
			seed: s0,
			limit: 8,
			direction: "out"
		});
		var snap = BagBuiltins.materialize(harness, bag);
		Assert.equals(2, snap.size());
		Assert.isTrue(snap.weights.exists(s1));
		Assert.isTrue(snap.weights.exists(s2));
		Assert.equals(0.5, snap.weightOf(s1));
	}

	public function testComputedBagStrategyInterp() {
		var src = '
strategy ComputedBag {
  param topN = 3
  param look = 5
  onBar {
    portfolio_apply(bag_rank_mom(topN, look, "tops"))
  }
}
';
		var prog = new MuseParser().parse(src, "computed-bag.ms");
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(6, 50, 13);
		var result = new MuseInterp(harness).runPanelBacktest(prog, panel);
		Assert.isTrue(result.trades > 0, "trades=" + result.trades);
		Assert.isTrue(result.finalEquity > 0);
	}

	public function testBagComputedClosure() {
		var harness = new HarnessContext();
		harness.resetForTrial(100000);
		var panel = PanelFeed.synthetic(3, 15, 1);
		musescript.builtins.PortfolioBuiltins.observePanel(harness, panel, 8);
		harness.currentBar = panel.all()[8];
		var s0 = panel.symbols[0];
		harness.invokeUserFn = function(f:Dynamic, args:Array<Dynamic>):Dynamic {
			return Reflect.callMethod(null, f, args != null ? args : []);
		};
		var bag = BagBuiltins.bagComputed("fn", function() {
			return BagBuiltins.bagEqual([s0], "one");
		});
		Assert.isTrue(bag.isComputed());
		var snap = BagBuiltins.materialize(harness, bag);
		Assert.equals(1, snap.size());
		Assert.equals(1.0, snap.weightOf(s0));
	}
}
