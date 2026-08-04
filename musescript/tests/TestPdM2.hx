package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.DataFrame;
import musescript.dataframe.FrameWindow;
import musescript.dataframe.GroupBy;
import musescript.dataframe.Index;
import musescript.dataframe.Pd;
import musescript.dataframe.Series;
import musescript.builtins.MuseHost;
import musescript.builtins.PdBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;

/**
 * muse.pd M2 — groupby agg/transform/rank, xs_rank, shift/diff/pct_change, rolling/ewm.
 */
class TestPdM2 extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] got ${actual[i]} want ${expected[i]}');
	}

	/** Long panel: (date, symbol_id, score). */
	function longFactor():DataFrame {
		return DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 1., 2., 2., 2.]),
			"sym" => Np.asarray([0., 1., 2., 0., 1., 2.]),
			"score" => Np.asarray([10., 30., 20., 5., 15., 25.])
		], null, ["t", "sym", "score"]);
	}

	public function testGroupbyMeanAgg() {
		var df = longFactor();
		var g = Pd.groupbyAgg(df, "t", "mean");
		Assert.equals(2, g.nrows());
		assertSeries([20., 15.], g.get("score").toArray(), "mean by t");
		Assert.equals(2, g.ncols()); // sym + score (no t col; t is index)
		var idx = Index.asF64(g.index);
		Assert.notNull(idx);
		Assert.equals(1.0, idx.get(0));
		Assert.equals(2.0, idx.get(1));
	}

	public function testGroupbySumMinMaxCount() {
		var df = longFactor();
		assertSeries([60., 45.], Pd.groupbyAgg(df, "t", "sum").get("score").toArray(), "sum");
		assertSeries([10., 5.], Pd.groupbyAgg(df, "t", "min").get("score").toArray(), "min");
		assertSeries([30., 25.], Pd.groupbyAgg(df, "t", "max").get("score").toArray(), "max");
		assertSeries([3., 3.], Pd.groupbyAgg(df, "t", "count").get("score").toArray(), "count");
	}

	public function testGroupbyTransformMeanAndZscore() {
		var df = longFactor();
		var tr = Pd.groupbyTransform(df, "t", "mean");
		assertSeries([20., 20., 20., 15., 15., 15.], tr.get("score").toArray(), "transform mean");
		Assert.same(df.get("t").toArray(), tr.get("t").toArray());

		var z = Pd.groupbyTransform(df, "t", "zscore");
		// date 1: [10,30,20] mean=20 std=10 → [-1,1,0]
		assertSeries([-1., 1., 0., -1., 0., 1.], z.get("score").toArray(), "zscore");
	}

	public function testGroupbyRankCrossSection() {
		var df = longFactor();
		var ranked = Pd.groupbyRank(df, "t");
		// t=1: 10,30,20 → ranks 1,3,2; t=2: 5,15,25 → 1,2,3
		assertSeries([1., 3., 2., 1., 2., 3.], ranked.get("score").toArray(), "groupby rank");
		var pct = Pd.groupbyRank(df, "t", true);
		assertSeries([1. / 3., 1., 2. / 3., 1. / 3., 2. / 3., 1.], pct.get("score").toArray(), "pct rank");
	}

	public function testRankTiesAverage() {
		var s = Series.fromArray([1., 2., 2., 4.]);
		assertSeries([1., 2.5, 2.5, 4.], s.rank().toArray(), "avg ties");
	}

	public function testXsRankWidePanel() {
		// One row = cross-section across symbols
		var wide = DataFrame.fromColumns([
			"A" => Np.asarray([10., 5.]),
			"B" => Np.asarray([30., 15.]),
			"C" => Np.asarray([20., 25.])
		], Index.fromFloats([1., 2.]), ["A", "B", "C"]);
		var xs = Pd.xsRank(wide);
		assertSeries([1., 1.], xs.get("A").toArray(), "A");
		assertSeries([3., 2.], xs.get("B").toArray(), "B");
		assertSeries([2., 3.], xs.get("C").toArray(), "C");
	}

	public function testShiftDiffPctChange() {
		var s = Series.fromArray([10., 12., 15., 12.]);
		assertSeries([Math.NaN, 10., 12., 15.], s.shift(1).toArray(), "shift");
		assertSeries([Math.NaN, 2., 3., -3.], s.diff(1).toArray(), "diff");
		assertSeries([Math.NaN, 0.2, 0.25, -0.2], s.pctChange(1).toArray(), "pct");

		var df = DataFrame.fromColumns(["x" => Np.asarray([1., 2., 4.])], null, ["x"]);
		assertSeries([Math.NaN, 1., 2.], df.shift(1).get("x").toArray(), "frame shift");
	}

	public function testRollingMeanAndStd() {
		var s = Series.fromArray([1., 2., 3., 4., 5.]);
		assertSeries([Math.NaN, Math.NaN, 2., 3., 4.], s.rollingMean(3).toArray(), "roll mean");
		// window of [1,2,3]: std sample = sqrt(1)=1
		var std = s.rollingStd(3).toArray();
		Assert.isTrue(Math.isNaN(std[0]) && Math.isNaN(std[1]));
		Assert.isTrue(approxEq(1.0, std[2]));
	}

	public function testEwmMeanSpan() {
		var s = Series.fromArray([1., 2., 3.]);
		var span = 3;
		var alpha = 2.0 / (span + 1.0); // 0.5
		var e = s.ewmMean(span).toArray();
		Assert.equals(1.0, e[0]);
		Assert.isTrue(approxEq(alpha * 2 + (1 - alpha) * 1, e[1]));
		Assert.isTrue(approxEq(alpha * 3 + (1 - alpha) * e[1], e[2]));
	}

	public function testRollingIsCausalPrefixNaN() {
		// Documents PIT: rolling does not look ahead; first window-1 are NaN.
		var s = Series.fromArray([100., 101., 102., 110.]);
		var out = FrameWindow.rollingMeanSeries(s, 2).toArray();
		Assert.isTrue(Math.isNaN(out[0]));
		Assert.isTrue(approxEq(100.5, out[1]));
		Assert.isTrue(approxEq(101.5, out[2]));
	}

	public function testPdBuiltinsGroupbyAndXsRank() {
		var df = longFactor();
		var mean = PdBuiltins.groupbyMean(df, "t");
		assertSeries([20., 15.], mean.get("score").toArray(), "builtins mean");
		var xs = PdBuiltins.xsRank(DataFrame.fromColumns([
			"a" => Np.asarray([3.]),
			"b" => Np.asarray([1.]),
			"c" => Np.asarray([2.])
		], null, ["a", "b", "c"]));
		Assert.equals(3., xs.get("a").getFlat(0));
		Assert.equals(1., xs.get("b").getFlat(0));
		Assert.equals(2., xs.get("c").getFlat(0));
	}

	public function testHostLowerXsRank() {
		Assert.equals("pd_xs_rank", MuseHost.resolveFlat("pd", "xs_rank"));
		Assert.equals("pd_groupby_rank", MuseHost.resolveFlat("pd", "groupby_rank"));
		Assert.equals("pd_shift", MuseHost.resolveFlat("pd", "shift"));
		var src = '
			strategy S {
			  onBar {
			    var df = muse.pd.from_columns({a: [1, 2], b: [3, 4]})
			    var r = muse.pd.xs_rank(df)
			    var g = muse.pd.groupby_rank(df, "a")
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_xs_rank(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_groupby_rank(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.pd") < 0, printed);
	}

	public function testInterpGroupbyRankSmoke() {
		var src = '
			@strategy("pd-m2")
			@on(bar) {
				var scores = muse.pd.from_columns({
					t: [1, 1, 1],
					score: [10, 30, 20]
				});
				var ranked = muse.pd.groupby_rank(scores, "t");
				var col = muse.pd.get(ranked, "score");
				var vals = muse.pd.series_values(col);
				if (muse.np.sum(vals) == 6) long();
			}
		';
		var bars = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testFactorToXsRankRecipe() {
		// Trading recipe: long factor → groupby date rank → top scores are highest ranks.
		var long = longFactor();
		var ranked = GroupBy.create(long, "t").rank();
		var t1 = ranked.iloc([0, 1, 2]).get("score").toArray();
		Assert.equals(3., t1[1]); // score 30 → rank 3
		var wide = DataFrame.fromColumns([
			"AAA" => Np.asarray([0.1, 0.4]),
			"BBB" => Np.asarray([0.3, 0.2]),
			"CCC" => Np.asarray([0.2, 0.5])
		], null, ["AAA", "BBB", "CCC"]);
		var xr = wide.xsRank();
		// row0: AAA=1 BBB=3 CCC=2 — BBB top for rebalance_equal / bag
		Assert.equals(3., xr.get("BBB").getFlat(0));
	}
}
