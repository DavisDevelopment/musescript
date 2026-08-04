package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.Palette;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.parse.MuseParser;

/**
 * Closed gated NP_* / PD_* evo palette: Expand shapes, growth off by default,
 * optional Expand→run smoke. No open-world muse.np / muse.pd trees.
 */
class TestNpPdEvoPalette extends Test {
	static function genome(entry:BoolNode, ?size:ScalarNode):StrategyGenome {
		return {
			name: "NpPdGate",
			params: [],
			entryLong: entry,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: size != null ? size : KConst(1.0)
		};
	}

	public function testPaletteCatalogClosed() {
		Assert.same(["mean", "dot", "sum"], Palette.NP_OPS);
		Assert.same(["xs_rank"], Palette.PD_OPS);
		Assert.equals(55, Palette.NP_MAX_WIN);
		Assert.isTrue(Palette.npWindows().indexOf(89) < 0);
		Assert.isTrue(Palette.npWindows().indexOf(5) >= 0);
		Assert.same([], Palette.npOpsFor([]));
		Assert.same(["mean"], Palette.npOpsFor(["mean", "bogus"]));
		Assert.same(Palette.NP_OPS, Palette.npOpsFor(null));
	}

	public function testExpandNpMeanDotSum() {
		var mean = Expand.npExpr("mean", SPrice("close"), 5, null);
		Assert.equals("np_mean(window(close, 5))", mean);
		var sum = Expand.npExpr("sum", SInd("sma", "close", 8, null), 3, null);
		Assert.equals('np_sum(window(sma("close", 8), 3))', sum);
		var dot = Expand.npExpr("dot", SPrice("close"), 3, SPrice("high"));
		Assert.equals("np_dot(window(close, 3), window(high, 3))", dot);
		var clamped = Expand.npExpr("mean", SPrice("close"), 200, null);
		Assert.equals('np_mean(window(close, ${Palette.NP_MAX_WIN}))', clamped);

		var g = genome(BCmp(">", KNp("mean", SPrice("close"), 5, null), KConst(10.0)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("np_mean(window(close, 5))") >= 0, src);
		Assert.isTrue(src.indexOf("muse.np") < 0, src);
		Assert.isTrue(src.indexOf("long(") >= 0, src);
	}

	public function testExpandPdXsRankLiteralUniverse() {
		var expr = Expand.pdExpr("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]);
		Assert.isTrue(expr.indexOf("pd_xs_rank(") >= 0, expr);
		Assert.isTrue(expr.indexOf(", true)") >= 0, expr); // percentile ranks → target_weight-safe
		Assert.isTrue(expr.indexOf("pd_from_columns(") >= 0, expr);
		Assert.isTrue(expr.indexOf('mom_of("AAA", 5)') >= 0, expr);
		Assert.isTrue(expr.indexOf('mom_of("BBB", 5)') >= 0, expr);
		Assert.isTrue(expr.indexOf('pd_get(') >= 0 && expr.indexOf('"AAA"') >= 0, expr);
		Assert.isTrue(expr.indexOf("np_get_flat(") >= 0, expr);
		Assert.isTrue(expr.indexOf("groupby") < 0, expr);
		Assert.isTrue(expr.indexOf("merge") < 0, expr);

		// KPd without explicit PanelAction: Expand coerces to target_weight (not long/short).
		var g = genome(BCmp(">",
			KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]),
			KConst(0.5)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("pd_xs_rank(") >= 0, src);
		Assert.isTrue(src.indexOf("muse.pd") < 0, src);
		Assert.isTrue(src.indexOf("target_weight(") >= 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		Assert.isTrue(Expand.inferPanelActionForPd(g) != null);
		Assert.isTrue(Expand.hasKPd(g));
	}

	public function testGrowthGatedOffByDefault() {
		var v = new Variation(99);
		for (_ in 0...60) {
			var src = Expand.expand(v.randomGenome(3));
			Assert.isTrue(src.indexOf("np_mean(") < 0, src);
			Assert.isTrue(src.indexOf("np_dot(") < 0, src);
			Assert.isTrue(src.indexOf("np_sum(") < 0, src);
			Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
			Assert.isTrue(src.indexOf("pd_from_columns(") < 0, src);
		}
	}

	public function testGrowthNpWhenConfigured() {
		var v = new Variation(3);
		v.configureForNp(null);
		var hit = false;
		for (_ in 0...120) {
			var src = Expand.expand(v.randomGenome(2));
			if (src.indexOf("np_mean(") >= 0 || src.indexOf("np_dot(") >= 0
					|| src.indexOf("np_sum(") >= 0) {
				hit = true;
				Assert.isTrue(src.indexOf("muse.np") < 0, src);
				break;
			}
		}
		Assert.isTrue(hit, "expected KNp growth under configureForNp");
	}

	public function testGrowthPdNeedsUniverse() {
		var noUni = new Variation(5);
		noUni.configureForPd(null);
		for (_ in 0...40) {
			var src = Expand.expand(noUni.randomGenome(2));
			Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
		}
		var v = new Variation(11);
		v.configureForUniverse(["AAA", "BBB"]);
		v.configureForPd(["xs_rank"]);
		var hit = false;
		for (_ in 0...120) {
			var g = v.randomGenome(2);
			var src = Expand.expand(g);
			if (src.indexOf("pd_xs_rank(") >= 0) {
				hit = true;
				Assert.isTrue(src.indexOf("groupby") < 0, src);
				// Under PD gate: panel HostABI, never classic long/short ignoring xs.
				Assert.isTrue(src.indexOf("long(") < 0, src);
				Assert.isTrue(
					src.indexOf("target_weight(") >= 0
					|| src.indexOf("buy(") >= 0
					|| src.indexOf("rebalance_equal(") >= 0,
					src);
				Assert.isTrue(g.panelAction != null || Expand.hasKPd(g));
				break;
			}
		}
		Assert.isTrue(hit, "expected KPd xs_rank under configureForPd + universe");
	}

	#if (js || python)
	public function testExpandNpMeanInterpSmoke() {
		var g = genome(BCmp(">", KNp("mean", SPrice("close"), 3, null), KConst(0.0)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("np_mean(window(close, 3))") >= 0, src);
		var bars = BarFeed.synthetic(40, 7).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok, "backend=" + r.backend + " err=" + r.error + " src=\n" + src);
	}

	public function testExpandPdXsRankInterpSmoke() {
		// Hand-expanded shape must parse + run on interp (WASM all-U for pd_*).
		var src = '
			@strategy("pd-evo-smoke")
			@on(bar) {
				if (np_get_flat(pd_series_values(pd_get(pd_xs_rank(pd_from_columns({
					AAA: [1.0],
					BBB: [2.0]
				}), true), "BBB")), 0) > 0.5) long(1);
			}
		';
		var bars = [for (i in 0...5) {
			open: 1., high: 1., low: 1., close: 1., volume: 1.,
			time: (i : Float), index: i, data: null
		}];
		var r = new musescript.interp.MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades >= 0);
	}
	#end
}
