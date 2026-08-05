package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.AnyDataFrame;
import musescript.dataframe.AnyPdSeries;
import musescript.dataframe.AnyPdValues;
import musescript.dataframe.DataFrame;
import musescript.dataframe.FrameCorr;
import musescript.dataframe.FrameReshape;
import musescript.dataframe.GroupBy;
import musescript.dataframe.Index;
import musescript.dataframe.Pd;
import musescript.dataframe.Series;
import musescript.builtins.MuseHost;
import musescript.builtins.PdBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StrategyWasmEmitter;
import musescript.compile.WasmPdEligibility;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;

/**
 * muse.pd M3 — pivot/melt, multi-key groupby, corr/cov, sealed Any*, WASM_PD honesty.
 */
class TestPdM3 extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] got ${actual[i]} want ${expected[i]}');
	}

	function longPanel():DataFrame {
		return DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 2., 2.]),
			"sym" => Np.asarray([0., 1., 0., 1.]),
			"score" => Np.asarray([10., 20., 30., 40.])
		], null, ["t", "sym", "score"]);
	}

	public function testPivotWide() {
		var long = longPanel();
		var wide = Pd.pivot(long, "t", "sym", "score");
		Assert.equals(2, wide.nrows());
		Assert.equals(2, wide.ncols());
		assertSeries([10., 30.], wide.get("0").toArray(), "sym0");
		assertSeries([20., 40.], wide.get("1").toArray(), "sym1");
		var idx = Index.asF64(wide.index);
		Assert.notNull(idx);
		Assert.equals(1.0, idx.get(0));
		Assert.equals(2.0, idx.get(1));
	}

	public function testMeltRoundTripCodes() {
		var wide = DataFrame.fromColumns([
			"0" => Np.asarray([10., 30.]),
			"1" => Np.asarray([20., 40.])
		], Index.fromFloats([1., 2.]), ["0", "1"]);
		var melted = Pd.melt(wide, null, null, "sym", "score");
		Assert.equals(4, melted.nrows());
		assertSeries([0., 0., 1., 1.], melted.get("sym").toArray(), "sym codes");
		assertSeries([10., 30., 20., 40.], melted.get("score").toArray(), "scores");
	}

	public function testMeltWithIdVars() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([1., 2.]),
			"A" => Np.asarray([10., 30.]),
			"B" => Np.asarray([20., 40.])
		], null, ["t", "A", "B"]);
		var m = FrameReshape.melt(df, ["t"], ["A", "B"], "variable", "value");
		Assert.equals(4, m.nrows());
		assertSeries([1., 2., 1., 2.], m.get("t").toArray(), "id");
		assertSeries([0., 0., 1., 1.], m.get("variable").toArray(), "ord");
		assertSeries([10., 30., 20., 40.], m.get("value").toArray(), "val");
	}

	public function testMultiKeyGroupbyAgg() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 1., 2.]),
			"sec" => Np.asarray([0., 0., 1., 0.]),
			"x" => Np.asarray([10., 20., 30., 40.])
		], null, ["t", "sec", "x"]);
		var g = Pd.groupbyKeysAgg(df, ["t", "sec"], "mean");
		Assert.equals(3, g.nrows());
		Assert.isTrue(g.hasColumn("t") && g.hasColumn("sec") && g.hasColumn("x"));
		// groups (1,0)->15, (1,1)->30, (2,0)->40
		assertSeries([15., 30., 40.], g.get("x").toArray(), "multi mean");
		assertSeries([1., 1., 2.], g.get("t").toArray(), "t col");
		assertSeries([0., 1., 0.], g.get("sec").toArray(), "sec col");
	}

	public function testMultiKeyRank() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 1., 1.]),
			"sec" => Np.asarray([0., 0., 1., 1.]),
			"x" => Np.asarray([5., 15., 10., 20.])
		], null, ["t", "sec", "x"]);
		var ranked = GroupBy.createKeys(df, ["t", "sec"]).rank();
		assertSeries([1., 2., 1., 2.], ranked.get("x").toArray(), "rank within (t,sec)");
	}

	public function testCorrPearson() {
		var df = DataFrame.fromColumns([
			"a" => Np.asarray([1., 2., 3., 4.]),
			"b" => Np.asarray([2., 4., 6., 8.]),
			"c" => Np.asarray([4., 3., 2., 1.])
		], null, ["a", "b", "c"]);
		var c = Pd.corr(df);
		Assert.equals(3, c.nrows());
		Assert.equals(3, c.ncols());
		Assert.isTrue(approxEq(1.0, c.get("a").getFlat(0)));
		Assert.isTrue(approxEq(1.0, c.get("b").getFlat(0))); // a vs b perfect
		Assert.isTrue(approxEq(-1.0, c.get("c").getFlat(0))); // a vs c anti
		var cov = FrameCorr.cov(df);
		Assert.isTrue(approxEq(c.get("a").getFlat(0), 1.0));
		Assert.isTrue(!Math.isNaN(cov.get("a").getFlat(0)));
	}

	public function testSealedAnyHandles() {
		var df = DataFrame.fromColumns(["x" => Np.asarray([1.])], null, ["x"]);
		var boxed:AnyDataFrame = AnyPdValues.ofFrame(df);
		Assert.equals(1, AnyPdValues.unwrapFrame(boxed).nrows());
		var s = Series.fromArray([1., 2.], null, "s");
		var bs:AnyPdSeries = AnyPdValues.ofSeries(s);
		Assert.equals(2, AnyPdValues.unwrapSeries(bs).length);
		Assert.equals("dataframe", AnyPdValues.kindOf(df));
		Assert.equals("series", AnyPdValues.kindOf(s));
	}

	public function testWasmPdEligibilityHonesty() {
		// M4 claims pd_rank1d as tiny N; frames remain escape / opaque U.
		Assert.equals(0, WasmPdEligibility.NATIVE_SCALAR.length);
		Assert.isTrue(WasmPdEligibility.NATIVE_VEC.indexOf("pd_rank1d") >= 0);
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_pivot"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_xs_rank"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_corr"));
		Assert.isFalse(WasmPdEligibility.isClaimedNative("pd_xs_rank"));
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_rank1d"));
		Assert.isTrue(StrategyWasmEmitter.PD_HOST_ESCAPE.indexOf("pd_melt") >= 0);
	}

	public function testWasmOpaqueFallbackOnPd() {
		var src = '
			strategy PdOpaque {
				onBar {
					var df = muse.pd.from_columns({a: [1, 2], b: [3, 4]})
					var r = muse.pd.xs_rank(df)
					when muse.pd.nrows(r) == 2: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		// Opaque TDataFrame → whole-module fallback (null WAT), not surprise native.
		Assert.isNull(wat, "pd_* returning DataFrame must fail closed to interp/JS");
	}

	public function testHostLowerPivotCorr() {
		Assert.equals("pd_pivot", MuseHost.resolveFlat("pd", "pivot"));
		Assert.equals("pd_corr", MuseHost.resolveFlat("pd", "corr"));
		Assert.equals("pd_groupby_keys_agg", MuseHost.resolveFlat("pd", "groupby_keys_agg"));
		var src = '
			strategy S {
			  onBar {
			    var df = muse.pd.from_columns({t: [1, 1], sym: [0, 1], score: [10, 20]})
			    var w = muse.pd.pivot(df, "t", "sym", "score")
			    var c = muse.pd.corr(w)
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_pivot(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_corr(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.pd") < 0, printed);
	}

	public function testInterpPivotSmoke() {
		var src = '
			@strategy("pd-m3")
			@on(bar) {
				var panel = muse.pd.from_columns({
					t: [1, 1, 2, 2],
					sym: [0, 1, 0, 1],
					score: [10, 20, 30, 40]
				});
				var wide = muse.pd.pivot(panel, "t", "sym", "score");
				if (muse.pd.nrows(wide) == 2 && muse.pd.ncols(wide) == 2) long();
			}
		';
		var bars = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testPdBuiltinsPivotCorr() {
		var long = longPanel();
		var wide = PdBuiltins.pivotOf(long, "t", "sym", "score");
		assertSeries([10., 30.], wide.get("0").toArray(), "builtins pivot");
		var c = PdBuiltins.corrOf(wide);
		Assert.equals(2, c.ncols());
	}
}
