package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.Palette;
import musescript.evo.PanelAction;
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
		Assert.same(["xs_rank", "shift"], Palette.PD_OPS);
		Assert.equals(55, Palette.NP_MAX_WIN);
		Assert.equals(34, Palette.PD_SHIFT_MAX);
		Assert.equals(64, Palette.PD_RANK1D_MAX);
		Assert.equals(musescript.compile.WasmPdEligibility.MAX_VEC_LEN, Palette.PD_RANK1D_MAX);
		Assert.same([1, 2, 3, 5], Palette.PD_BAG_TOP_KS);
		Assert.isTrue(Palette.npWindows().indexOf(89) < 0);
		Assert.isTrue(Palette.npWindows().indexOf(5) >= 0);
		Assert.isTrue(Palette.pdShiftPeriods().indexOf(55) < 0);
		Assert.isTrue(Palette.pdShiftPeriods().indexOf(5) >= 0);
		Assert.same([], Palette.npOpsFor([]));
		Assert.same(["mean"], Palette.npOpsFor(["mean", "bogus"]));
		Assert.same(Palette.NP_OPS, Palette.npOpsFor(null));
		Assert.same(["shift"], Palette.pdOpsFor(["shift", "bogus"]));
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

	public function testExpandPdXsRankRank1dWhenLe64() {
		var expr = Expand.pdExpr("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]);
		Assert.isTrue(expr.indexOf("pd_rank1d(") >= 0, expr);
		Assert.isTrue(expr.indexOf(", true)") >= 0, expr); // percentile ranks → target_weight-safe
		Assert.isTrue(expr.indexOf("pd_xs_rank(") < 0, expr);
		Assert.isTrue(expr.indexOf("pd_from_columns(") < 0, expr);
		Assert.isTrue(expr.indexOf('mom_of("AAA", 5)') >= 0, expr);
		Assert.isTrue(expr.indexOf('mom_of("BBB", 5)') >= 0, expr);
		Assert.isTrue(expr.indexOf("np_get_flat(") >= 0, expr);
		Assert.isTrue(expr.indexOf(", 0)") >= 0, expr); // AAA at index 0
		Assert.isTrue(expr.indexOf("groupby") < 0, expr);
		Assert.isTrue(expr.indexOf("merge") < 0, expr);

		var bIdx = Expand.pdExpr("xs_rank", "close", 0, "BBB", ["AAA", "BBB"]);
		Assert.isTrue(bIdx.indexOf("np_get_flat(pd_rank1d([") >= 0, bIdx);
		Assert.isTrue(bIdx.indexOf(", 1)") >= 0, bIdx);

		// KPd without explicit PanelAction: Expand coerces to target_weight (not long/short).
		var g = genome(BCmp(">",
			KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]),
			KConst(0.5)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
		Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
		Assert.isTrue(src.indexOf("muse.pd") < 0, src);
		Assert.isTrue(src.indexOf("target_weight(") >= 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		Assert.isTrue(Expand.inferPanelActionForPd(g) != null);
		Assert.isTrue(Expand.hasKPd(g));
	}

	public function testExpandPdXsRankFrameWhenGt64() {
		var syms = [for (i in 0...Palette.PD_RANK1D_MAX + 1) 'S$i'];
		var expr = Expand.pdExpr("xs_rank", "mom", 5, "S0", syms);
		Assert.isTrue(expr.indexOf("pd_xs_rank(") >= 0, expr);
		Assert.isTrue(expr.indexOf("pd_from_columns(") >= 0, expr);
		Assert.isTrue(expr.indexOf("pd_rank1d(") < 0, expr);
		Assert.isTrue(expr.indexOf(", true)") >= 0, expr);
		Assert.isTrue(expr.indexOf('mom_of("S0", 5)') >= 0, expr);
		Assert.isTrue(expr.indexOf('pd_get(') >= 0 && expr.indexOf('"S0"') >= 0, expr);
	}

	public function testGrowthGatedOffByDefault() {
		var v = new Variation(99);
		for (_ in 0...60) {
			var src = Expand.expand(v.randomGenome(3));
			Assert.isTrue(src.indexOf("np_mean(") < 0, src);
			Assert.isTrue(src.indexOf("np_dot(") < 0, src);
			Assert.isTrue(src.indexOf("np_sum(") < 0, src);
			Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
			Assert.isTrue(src.indexOf("pd_rank1d(") < 0, src);
			Assert.isTrue(src.indexOf("pd_shift(") < 0, src);
			Assert.isTrue(src.indexOf("pd_from_columns(") < 0, src);
			Assert.isTrue(src.indexOf("bag_from_scan(") < 0, src);
			Assert.isTrue(src.indexOf("bag_from_dict(") < 0, src);
			Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
			Assert.isTrue(src.indexOf("bag_computed(") < 0, src);
			Assert.isTrue(src.indexOf("portfolio_apply(") < 0, src);
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
			Assert.isTrue(src.indexOf("pd_rank1d(") < 0, src);
		}
		var v = new Variation(11);
		v.configureForUniverse(["AAA", "BBB"]);
		v.configureForPd(["xs_rank"]);
		var hit = false;
		for (_ in 0...120) {
			var g = v.randomGenome(2);
			var src = Expand.expand(g);
			if (src.indexOf("pd_rank1d(") >= 0 || src.indexOf("pd_xs_rank(") >= 0) {
				hit = true;
				Assert.isTrue(src.indexOf("groupby") < 0, src);
				// Small universe → packed rank1d, not opaque frame.
				Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
				Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
				// Under PD gate: panel HostABI, never classic long/short ignoring xs.
				Assert.isTrue(src.indexOf("long(") < 0, src);
				Assert.isTrue(
					src.indexOf("target_weight(") >= 0
					|| src.indexOf("buy(") >= 0
					|| src.indexOf("rebalance_equal(") >= 0
					|| src.indexOf("portfolio_apply(") >= 0,
					src);
				Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
				Assert.isTrue(src.indexOf("symbols()") < 0, src);
				Assert.isTrue(g.panelAction != null || Expand.hasKPd(g));
				break;
			}
		}
		Assert.isTrue(hit, "expected KPd xs_rank under configureForPd + universe");
	}

	public function testExpandBagScanTopClosedShape() {
		var g = genome(
			BCmp(">", KConst(1.0), KConst(0.0)),
			KConst(1.0)
		);
		g.panelAction = PABagScanTop("mom", 5, 1, ["AAA", "BBB"]);
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("portfolio_apply(bag_from_scan(") >= 0, src);
		Assert.isTrue(src.indexOf("{AAA: mom_of(\"AAA\", 5), BBB: mom_of(\"BBB\", 5)}") >= 0
			|| (src.indexOf('mom_of("AAA", 5)') >= 0 && src.indexOf('mom_of("BBB", 5)') >= 0), src);
		Assert.isTrue(src.indexOf(", 1)") >= 0, src);
		Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
		Assert.isTrue(src.indexOf("bag_computed(") < 0, src);
		Assert.isTrue(src.indexOf("symbols()") < 0, src);
		Assert.isTrue(src.indexOf("dict_new") < 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		Assert.isTrue(src.indexOf('sell_all("AAA")') >= 0, src);
		Assert.equals(2, Expand.clampBagTopK(99, ["AAA", "BBB"]));
		Assert.equals(1, Expand.clampBagTopK(0, ["AAA", "BBB"]));
		Assert.equals(1, Expand.clampBagTopK(1, ["AAA"]));
	}

	public function testExpandBagRankWeightsClosedShape() {
		var g = genome(BCmp(">", KConst(1.0), KConst(0.0)));
		g.panelAction = PABagRankWeights("mom", 5, ["AAA", "BBB"]);
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("portfolio_apply(bag_norm(bag_from_dict(") >= 0, src);
		Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
		Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
		Assert.isTrue(src.indexOf("bag_rank_rsi(") < 0, src);
		Assert.isTrue(src.indexOf("symbols()") < 0, src);
		Assert.isTrue(src.indexOf("long(") < 0, src);
		var dict = Expand.panelRankWeightDict("close", 0, ["AAA", "BBB"]);
		Assert.isTrue(dict.indexOf("AAA:") >= 0 && dict.indexOf("BBB:") >= 0, dict);
		Assert.equals('{AAA: close_of("AAA"), BBB: close_of("BBB")}',
			Expand.panelScoreDict("close", 0, ["AAA", "BBB"]));
	}

	public function testGrowthBagTemplatesUnderPdUniverse() {
		var v = new Variation(23);
		v.configureForUniverse(["AAA", "BBB"]);
		v.configureForPd(["xs_rank"]);
		var scanHit = false;
		var rwHit = false;
		for (_ in 0...200) {
			var g = v.randomGenome(2);
			if (g.panelAction == null) continue;
			var src = Expand.expand(g);
			Assert.isTrue(src.indexOf("bag_rank_mom(") < 0, src);
			Assert.isTrue(src.indexOf("bag_computed(") < 0, src);
			Assert.isTrue(src.indexOf("symbols()") < 0, src);
			switch (g.panelAction) {
				case PABagScanTop(_, _, _, _):
					scanHit = true;
					Assert.isTrue(src.indexOf("bag_from_scan(") >= 0, src);
					Assert.isTrue(src.indexOf("portfolio_apply(") >= 0, src);
				case PABagRankWeights(_, _, _):
					rwHit = true;
					Assert.isTrue(src.indexOf("bag_from_dict(") >= 0, src);
					Assert.isTrue(src.indexOf("portfolio_apply(") >= 0, src);
				default:
			}
			if (scanHit && rwHit) break;
		}
		Assert.isTrue(scanHit, "expected PABagScanTop under configureForPd + universe");
		Assert.isTrue(rwHit, "expected PABagRankWeights under configureForPd + universe");
	}

	public function testUniverseAloneDoesNotGrowBags() {
		var v = new Variation(31);
		v.configureForUniverse(["AAA", "BBB"]);
		for (_ in 0...80) {
			var g = v.randomGenome(2);
			if (g.panelAction == null) continue;
			switch (g.panelAction) {
				case PABagScanTop(_, _, _, _) | PABagRankWeights(_, _, _):
					Assert.fail("bags must stay PD-gated");
				default:
			}
			var src = Expand.expand(g);
			Assert.isTrue(src.indexOf("bag_from_scan(") < 0, src);
			Assert.isTrue(src.indexOf("bag_from_dict(") < 0, src);
		}
	}

	public function testExpandPdShiftSizeSafe() {
		var expr = Expand.pdExpr("shift", "close", 5, "", []);
		Assert.isTrue(expr.indexOf("pd_shift(") >= 0, expr);
		Assert.isTrue(expr.indexOf("pd_series(window(close, 6))") >= 0, expr);
		Assert.isTrue(expr.indexOf("np_get_flat(") >= 0, expr);
		Assert.isTrue(expr.indexOf("groupby") < 0, expr);
		Assert.isTrue(expr.indexOf("merge") < 0, expr);
		// Oversize periods clamp to PD_SHIFT_MAX.
		var big = Expand.pdShiftExpr("high", 200);
		Assert.isTrue(big.indexOf('pd_shift(pd_series(window(high, ${Palette.PD_SHIFT_MAX + 1})), ${Palette.PD_SHIFT_MAX})') >= 0, big);

		var g = genome(BCmp(">", KPd("shift", "close", 3, "", []), KConst(0.0)));
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("pd_shift(") >= 0, src);
		Assert.isTrue(src.indexOf("muse.pd") < 0, src);
		Assert.isTrue(Expand.hasKPd(g));
		Assert.isFalse(Expand.hasKPdXsRank(g));
		Assert.isFalse(Fitness.usesPanelFitness(g), "shift alone must not force panel fitness");
		Assert.isTrue(src.indexOf("long(") >= 0, src); // classic skeleton OK for shift
	}

	public function testGrowthPdShiftWithoutUniverse() {
		var v = new Variation(17);
		v.configureForPd(["shift"]);
		var hit = false;
		for (_ in 0...120) {
			var g = v.randomGenome(2);
			var src = Expand.expand(g);
			if (src.indexOf("pd_shift(") >= 0) {
				hit = true;
				Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
				Assert.isTrue(src.indexOf("pd_rank1d(") < 0, src);
				Assert.isTrue(src.indexOf("groupby") < 0, src);
				Assert.isTrue(Expand.hasKPd(g));
				Assert.isFalse(Expand.hasKPdXsRank(g));
				Assert.isFalse(Fitness.usesPanelFitness(g));
				break;
			}
		}
		Assert.isTrue(hit, "expected KPd shift under configureForPd without universe");
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

	/** Columnar NMA is the fast path for closed KNp over bar columns — parity vs Expand→JS. */
	public function testKNpPreferNmaParityVsExpand() {
		var g = genome(BCmp(">", KNp("mean", SPrice("close"), 5, null),
			KNp("sum", SPrice("open"), 3, null)));
		var bars = BarFeed.synthetic(60, 11).all();
		var prevNma = Fitness.preferNma;
		var prevVm = Fitness.preferVm;
		Fitness.preferNma = false;
		Fitness.preferVm = false;
		var ref = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(ref.ok, "ref " + ref.backend + " " + ref.error);
		Fitness.preferNma = true;
		var nma = Fitness.evaluate(g, bars, "js", false);
		Fitness.preferNma = prevNma;
		Fitness.preferVm = prevVm;
		Assert.isTrue(nma.ok, "nma " + nma.backend + " " + nma.error);
		Assert.equals("nma", nma.backend);
		Assert.equals(ref.trades, nma.trades);
		Assert.equals(
			haxe.io.FPHelper.doubleToI64(ref.finalEquity),
			haxe.io.FPHelper.doubleToI64(nma.finalEquity),
			"KNp NMA finalEquity bits vs Expand→JS");
	}

	/** preferVm remains the Expand→VM fast path for KNp when NMA is off. */
	public function testKNpPreferVmParityVsExpand() {
		var g = genome(BCmp(">", KNp("dot", SPrice("close"), 4, SPrice("high")), KConst(0.0)));
		var bars = BarFeed.synthetic(50, 3).all();
		var prevNma = Fitness.preferNma;
		var prevVm = Fitness.preferVm;
		Fitness.preferNma = false;
		Fitness.preferVm = false;
		var ref = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(ref.ok, "ref " + ref.error);
		Fitness.preferVm = true;
		var vm = Fitness.evaluate(g, bars, "js", false);
		Fitness.preferNma = prevNma;
		Fitness.preferVm = prevVm;
		Assert.isTrue(vm.ok, "vm " + vm.backend + " " + vm.error);
		Assert.equals("vm", vm.backend);
		Assert.equals(ref.trades, vm.trades);
		Assert.equals(
			haxe.io.FPHelper.doubleToI64(ref.finalEquity),
			haxe.io.FPHelper.doubleToI64(vm.finalEquity),
			"KNp VM finalEquity bits vs Expand→JS");
	}

	/** Closed KPd still refuses columnar NMA (gates / Expand-only). */
	public function testKPdStillNmaUnsupported() {
		var g = genome(BCmp(">", KPd("shift", "close", 3, "", []), KConst(0.0)));
		var bars = BarFeed.synthetic(30, 5).all();
		var prevNma = Fitness.preferNma;
		var prevVm = Fitness.preferVm;
		Fitness.preferNma = true;
		Fitness.preferVm = false;
		// PreferNma will fall through; compiled path must still work.
		var r = Fitness.evaluate(g, bars, "js", false);
		Fitness.preferNma = prevNma;
		Fitness.preferVm = prevVm;
		Assert.isTrue(r.ok, "KPd fallthrough compile " + r.backend + " " + r.error);
		Assert.notEquals("nma", r.backend, "KPd must not claim columnar NMA");
	}

	public function testExpandPdXsRankInterpSmoke() {
		// Hand-expanded shapes: packed rank1d (≤64) and frame xs_rank (>64 path).
		var src1d = '
			@strategy("pd-evo-smoke-rank1d")
			@on(bar) {
				if (np_get_flat(pd_rank1d([1.0, 2.0], true), 1) > 0.5) long(1);
			}
		';
		var bars = [for (i in 0...5) {
			open: 1., high: 1., low: 1., close: 1., volume: 1.,
			time: (i : Float), index: i, data: null
		}];
		var r1 = new musescript.interp.MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(src1d), new BarFeed(bars));
		Assert.isTrue(r1.trades >= 0);

		var srcFrame = '
			@strategy("pd-evo-smoke-frame")
			@on(bar) {
				if (np_get_flat(pd_series_values(pd_get(pd_xs_rank(pd_from_columns({
					AAA: [1.0],
					BBB: [2.0]
				}), true), "BBB")), 0) > 0.5) long(1);
			}
		';
		var r2 = new musescript.interp.MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(srcFrame), new BarFeed(bars));
		Assert.isTrue(r2.trades >= 0);
	}

	public function testExpandPdRank1dWasmNoHostEval() {
		if (!musescript.compile.StrategyWasmBackend.hostReady()) return;
		// Expand shape for |universe|≤64 must emit $vec_rank_pct without host_eval / opaque U.
		var g = genome(BCmp(">",
			KPd("xs_rank", "mom", 5, "AAA", ["AAA", "BBB"]),
			KConst(0.5)));
		g.panelAction = PATargetWeight("AAA");
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("pd_rank1d(") >= 0, src);
		Assert.isTrue(src.indexOf("pd_xs_rank(") < 0, src);
		var prog = musescript.compile.MuseHostLower.lower(new MuseParser().parse(src));
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat, "pd_rank1d Expand must not force opaque whole-module fallback\n" + src);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(
			wat.indexOf("call $vec_rank_pct") >= 0 || wat.indexOf("call $vec_rank") >= 0
			|| wat.indexOf("f64.const") >= 0,
			wat
		);
	}
	#end
}
