package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.Align;
import musescript.dataframe.Concat;
import musescript.dataframe.DataFrame;
import musescript.dataframe.FrameNa;
import musescript.dataframe.FrameReshape;
import musescript.dataframe.FrameWindow;
import musescript.dataframe.Index;
import musescript.dataframe.Join;
import musescript.dataframe.MergeAsof;
import musescript.dataframe.Pd;
import musescript.dataframe.PdParquet;
import musescript.ndarray.Np;

/**
 * String sidecar preservation through frame ops (concat/join/melt/align/…)
 * and Series-as-F64-only contract.
 */
class TestPdStrSidecar extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] got ${actual[i]} want ${expected[i]}');
	}

	function withSym(times:Array<Float>, xs:Array<Float>, syms:Array<String>):DataFrame {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray(times),
			"x" => Np.asarray(xs)
		], null, ["t", "x"]);
		return df.assignStr("sym", syms);
	}

	public function testAssignStrBasics() {
		var df = withSym([1., 2.], [10., 20.], ["AAPL", "MSFT"]);
		Assert.isTrue(df.hasStrColumn("sym"));
		Assert.isFalse(df.hasStrColumn("x"));
		Assert.same(["AAPL", "MSFT"], df.strValuesOf("sym"));
		Assert.same(["t", "x", "sym"], df.columns());
		Assert.equals("str", df.dtypes().get("sym"));
		Assert.equals("f64", df.dtypes().get("x"));
	}

	public function testSeriesF64OnlyForStrCols() {
		var df = withSym([1., 2.], [10., 20.], ["AAPL", "MSFT"]);
		var s = df.get("sym");
		Assert.equals(0, s.length);
		Assert.isNull(df.tryGet("sym"));
		Assert.isNull(df.tryGet("missing"));
		Assert.notNull(df.tryGet("x"));
		assertSeries([10., 20.], df.tryGet("x").toArray(), "tryGet x");
		Assert.same(["AAPL", "MSFT"], df.getStr("sym"));
		Assert.isNull(df.getStr("x"));
		Assert.same(["AAPL", "MSFT"], df.strValuesOf("sym"));
		assertSeries([10., 20.], df.get("x").toArray(), "f64 series");
	}

	public function testSelectDropCopyPreserve() {
		var df = withSym([1., 2.], [10., 20.], ["AAPL", "MSFT"]);
		var sel = df.select(["sym", "x"]);
		Assert.isTrue(sel.hasStrColumn("sym"));
		Assert.same(["AAPL", "MSFT"], sel.strValuesOf("sym"));
		assertSeries([10., 20.], sel.get("x").toArray(), "select x");
		var dropped = df.drop(["sym"]);
		Assert.isFalse(dropped.hasStrColumn("sym"));
		Assert.isTrue(dropped.hasColumn("x"));
		var cp = df.copy();
		Assert.same(["AAPL", "MSFT"], cp.strValuesOf("sym"));
	}

	public function testSliceIlocHeadPreserve() {
		var df = withSym([1., 2., 3.], [10., 20., 30.], ["A", "B", "C"]);
		Assert.same(["A", "B"], df.head(2).strValuesOf("sym"));
		Assert.same(["B", "C"], df.tail(2).strValuesOf("sym"));
		Assert.same(["A", "C"], df.iloc([0, 2]).strValuesOf("sym"));
		Assert.same(["B"], df.sliceRows(1, 2).strValuesOf("sym"));
	}

	public function testConcatAxis0UnionStr() {
		var a = withSym([1., 2.], [10., 20.], ["AAPL", "MSFT"]);
		var b = DataFrame.fromColumns(["t" => Np.asarray([3.]), "x" => Np.asarray([30.])], null, ["t", "x"])
			.assignStr("sym", ["GOOG"])
			.assignStr("exch", ["NASDAQ"]);
		var out = Pd.concat([a, b]);
		Assert.equals(3, out.nrows());
		Assert.isTrue(out.hasStrColumn("sym"));
		Assert.isTrue(out.hasStrColumn("exch"));
		Assert.same(["AAPL", "MSFT", "GOOG"], out.strValuesOf("sym"));
		Assert.same(["", "", "NASDAQ"], out.strValuesOf("exch"));
		assertSeries([10., 20., 30.], out.get("x").toArray(), "concat x");
	}

	public function testConcatAxis0MissingStrIsEmpty() {
		var a = withSym([1.], [10.], ["AAPL"]);
		var b = DataFrame.fromColumns(["t" => Np.asarray([2.]), "x" => Np.asarray([20.])], null, ["t", "x"]);
		var out = Concat.axis0([a, b]);
		Assert.same(["AAPL", ""], out.strValuesOf("sym"));
		assertSeries([10., 20.], out.get("x").toArray(), "vals");
	}

	public function testConcatAxis1StrSuffix() {
		var left = withSym([1., 2.], [10., 20.], ["AAPL", "MSFT"]);
		var right = DataFrame.fromColumns(["y" => Np.asarray([1., 2.])], null, ["y"])
			.assignStr("sym", ["X", "Y"]);
		var out = Pd.concatCols(left, right);
		Assert.isTrue(out.hasStrColumn("sym"));
		Assert.isTrue(out.hasStrColumn("sym_r"));
		Assert.same(["AAPL", "MSFT"], out.strValuesOf("sym"));
		Assert.same(["X", "Y"], out.strValuesOf("sym_r"));
		assertSeries([1., 2.], out.get("y").toArray(), "y");
	}

	public function testJoinLeftPreservesStr() {
		var left = withSym([1., 2., 3.], [10., 20., 30.], ["AAPL", "MSFT", "GOOG"]);
		var right = DataFrame.fromColumns([
			"t" => Np.asarray([1., 3.]),
			"fact" => Np.asarray([100., 300.])
		], null, ["t", "fact"]).assignStr("sector", ["tech", "tech"]);
		var out = Pd.join(left, right, "t", "left");
		Assert.equals(3, out.nrows());
		Assert.same(["AAPL", "MSFT", "GOOG"], out.strValuesOf("sym"));
		Assert.same(["tech", "", "tech"], out.strValuesOf("sector"));
		assertSeries([100., Math.NaN, 300.], out.get("fact").toArray(), "fact");
	}

	public function testJoinInnerStr() {
		var left = withSym([1., 2.], [10., 20.], ["A", "B"]);
		var right = DataFrame.fromColumns([
			"t" => Np.asarray([2., 9.]),
			"z" => Np.asarray([7., 8.])
		], null, ["t", "z"]).assignStr("tag", ["ok", "no"]);
		var out = Join.onColumn(left, right, "t", "inner");
		Assert.equals(1, out.nrows());
		Assert.same(["B"], out.strValuesOf("sym"));
		Assert.same(["ok"], out.strValuesOf("tag"));
		assertSeries([20.], out.get("x").toArray(), "x");
		assertSeries([7.], out.get("z").toArray(), "z");
	}

	public function testJoinOuterUnmatchedRightStr() {
		var left = withSym([1.], [10.], ["L"]);
		var right = DataFrame.fromColumns([
			"t" => Np.asarray([1., 2.]),
			"z" => Np.asarray([7., 8.])
		], null, ["t", "z"]).assignStr("tag", ["a", "b"]);
		var out = Pd.join(left, right, "t", "outer");
		Assert.equals(2, out.nrows());
		Assert.isTrue(out.hasStrColumn("sym"));
		Assert.isTrue(out.hasStrColumn("tag"));
		// First row match; second is unmatched right (left str empty).
		Assert.same(["L", ""], out.strValuesOf("sym"));
		Assert.same(["a", "b"], out.strValuesOf("tag"));
	}

	public function testJoinNameClashStrSuffix() {
		var left = withSym([1.], [10.], ["L"]);
		var right = DataFrame.fromColumns([
			"t" => Np.asarray([1.]),
			"x" => Np.asarray([99.])
		], null, ["t", "x"]).assignStr("sym", ["R"]);
		var out = Pd.join(left, right, "t", "left");
		Assert.same(["L"], out.strValuesOf("sym"));
		Assert.same(["R"], out.strValuesOf("sym_r"));
		assertSeries([10.], out.get("x").toArray(), "left x");
		assertSeries([99.], out.get("x_r").toArray(), "right x");
	}

	public function testMeltStrIdVars() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([0., 1.]),
			"A" => Np.asarray([10., 20.]),
			"B" => Np.asarray([30., 40.])
		], null, ["t", "A", "B"]).assignStr("sym", ["AAPL", "MSFT"]);
		var m = FrameReshape.melt(df, ["t", "sym"], ["A", "B"], "variable", "value");
		Assert.equals(4, m.nrows());
		Assert.isTrue(m.hasStrColumn("sym"));
		Assert.same(["AAPL", "MSFT", "AAPL", "MSFT"], m.strValuesOf("sym"));
		assertSeries([0., 1., 0., 1.], m.get("t").toArray(), "t");
		assertSeries([10., 20., 30., 40.], m.get("value").toArray(), "value");
	}

	public function testMeltDefaultSkipsStrValueCols() {
		var df = withSym([0., 1.], [10., 20.], ["A", "B"]).assign("y", Np.asarray([1., 2.]));
		// Default valueVars = all non-id F64; str not melted as values.
		var m = Pd.melt(df, ["t"], null, "variable", "value");
		Assert.isFalse(m.hasStrColumn("sym"));
		Assert.isTrue(m.hasColumn("x") == false);
		Assert.equals(4, m.nrows()); // x and y × 2 rows
	}

	public function testMeltWithSymIdOnly() {
		var df = DataFrame.fromColumns([
			"A" => Np.asarray([1., 2.]),
			"B" => Np.asarray([3., 4.])
		], null, ["A", "B"]).assignStr("sym", ["X", "Y"]);
		var m = Pd.melt(df, ["sym"], null, "v", "val");
		Assert.same(["X", "Y", "X", "Y"], m.strValuesOf("sym"));
		assertSeries([1., 2., 3., 4.], m.get("val").toArray(), "val");
	}

	public function testMeltStrValueVars() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([0., 1.])
		], null, ["t"])
			.assignStr("a", ["x", "y"])
			.assignStr("b", ["p", "q"]);
		var m = FrameReshape.melt(df, ["t"], ["a", "b"], "variable", "value");
		Assert.equals(4, m.nrows());
		Assert.isTrue(m.hasStrColumn("variable"));
		Assert.isTrue(m.hasStrColumn("value"));
		Assert.same(["a", "a", "b", "b"], m.strValuesOf("variable"));
		Assert.same(["x", "y", "p", "q"], m.strValuesOf("value"));
		assertSeries([0., 1., 0., 1.], m.get("t").toArray(), "t");
	}

	public function testMeltMixedValueVars() {
		var df = withSym([0., 1.], [10., 20.], ["A", "B"]).assignStr("tag", ["u", "v"]);
		var m = FrameReshape.melt(df, ["t"], ["x", "tag"], "variable", "value");
		Assert.equals(4, m.nrows());
		Assert.isTrue(m.hasStrColumn("variable"));
		Assert.isTrue(m.hasColumn("value"));
		Assert.isTrue(m.hasStrColumn("value_str"));
		Assert.same(["x", "x", "tag", "tag"], m.strValuesOf("variable"));
		assertSeries([10., 20., Math.NaN, Math.NaN], m.get("value").toArray(), "value");
		Assert.same(["", "", "u", "v"], m.strValuesOf("value_str"));
		assertSeries([0., 1., 0., 1.], m.get("t").toArray(), "t");
	}

	public function testXsRankPreservesStr() {
		var df = DataFrame.fromColumns([
			"AAA" => Np.asarray([3., 1.]),
			"BBB" => Np.asarray([1., 4.])
		], null, ["AAA", "BBB"]).assignStr("note", ["r0", "r1"]);
		var r = Pd.xsRank(df);
		Assert.same(["r0", "r1"], r.strValuesOf("note"));
		assertSeries([2., 1.], r.get("AAA").toArray(), "AAA rank");
		assertSeries([1., 2.], r.get("BBB").toArray(), "BBB rank");
	}

	public function testParquetFromColumnarStringColumn() {
		var df = PdParquet.fromColumnar({
			order: ["t", "sym", "x"],
			columns: {
				t: [1.0, 2.0],
				sym: ["AAPL", "MSFT"],
				x: [10.0, 20.0]
			}
		});
		Assert.isTrue(df.hasStrColumn("sym"));
		Assert.same(["AAPL", "MSFT"], df.strValuesOf("sym"));
		assertSeries([1., 2.], df.get("t").toArray(), "t");
		assertSeries([10., 20.], df.get("x").toArray(), "x");
		// Explicit strColumns map (Node helper optional shape).
		var df2 = PdParquet.fromColumnar({
			order: ["t", "sym"],
			columns: { t: [1.0, 2.0] },
			strOrder: ["sym"],
			strColumns: { sym: ["A", "B"] }
		});
		Assert.same(["A", "B"], df2.strValuesOf("sym"));
		assertSeries([1., 2.], df2.get("t").toArray(), "t2");
	}

	public function testPivotStrKeys() {
		var long = DataFrame.fromColumns([
			"t" => Np.asarray([0., 0., 1., 1.]),
			"score" => Np.asarray([10., 20., 30., 40.])
		], null, ["t", "score"]).assignStr("sym", ["AAPL", "MSFT", "AAPL", "MSFT"]);
		var wide = FrameReshape.pivot(long, "t", "sym", "score");
		Assert.equals(2, wide.nrows());
		Assert.isTrue(wide.hasColumn("AAPL"));
		Assert.isTrue(wide.hasColumn("MSFT"));
		assertSeries([10., 30.], wide.get("AAPL").toArray(), "AAPL");
		assertSeries([20., 40.], wide.get("MSFT").toArray(), "MSFT");
		// Str index + F64 columns key.
		var long2 = DataFrame.fromColumns([
			"k" => Np.asarray([0., 1., 0., 1.]),
			"score" => Np.asarray([1., 2., 3., 4.])
		], null, ["k", "score"]).assignStr("row", ["r0", "r0", "r1", "r1"]);
		var wide2 = Pd.pivot(long2, "row", "k", "score");
		Assert.equals("str", Index.kindOf(wide2.index));
		assertSeries([1., 3.], wide2.get("0").toArray(), "k0");
	}

	public function testPivotStillRequiresF64Values() {
		var bad = withSym([0., 1.], [10., 20.], ["A", "B"]);
		var empty = FrameReshape.pivot(bad, "t", "x", "sym");
		Assert.isTrue(empty.emptyFrame());
	}

	public function testAlignReindexPreserveStr() {
		var df = withSym([1., 2., 3.], [10., 20., 30.], ["A", "B", "C"]);
		df = DataFrame.fromColumns(
			["x" => df.valuesOf("x")],
			Index.fromFloats([1., 2., 3.]),
			["x"],
			["sym" => df.strValuesOf("sym")],
			["sym"]
		);
		var out = Align.reindex(df, Index.fromFloats([2., 9., 1.]));
		Assert.same(["B", "", "A"], out.strValuesOf("sym"));
		assertSeries([20., Math.NaN, 10.], out.get("x").toArray(), "reindex x");
	}

	public function testWindowOpsPreserveStr() {
		var df = withSym([1., 2., 3.], [10., 20., 30.], ["A", "B", "C"]);
		var sh = FrameWindow.shiftFrame(df, 1);
		Assert.same(["A", "B", "C"], sh.strValuesOf("sym"));
		assertSeries([Math.NaN, 10., 20.], sh.get("x").toArray(), "shift");
		var rm = df.rollingMean(2);
		Assert.same(["A", "B", "C"], rm.strValuesOf("sym"));
	}

	public function testFillnaDropnaIsnaStr() {
		var df = DataFrame.fromColumns([
			"x" => Np.asarray([1., Math.NaN, 3.])
		], null, ["x"]).assignStr("sym", ["A", "B", "C"]);
		var filled = FrameNa.fillna(df, 0.);
		Assert.same(["A", "B", "C"], filled.strValuesOf("sym"));
		assertSeries([1., 0., 3.], filled.get("x").toArray(), "fillna");
		var dropped = FrameNa.dropna(df);
		Assert.equals(2, dropped.nrows());
		Assert.same(["A", "C"], dropped.strValuesOf("sym"));
		var mask = FrameNa.isna(df);
		Assert.isFalse(mask.hasStrColumn("sym"));
		Assert.isTrue(mask.hasColumn("sym"));
		assertSeries([0., 1., 0.], mask.get("x").toArray(), "isna x");
		assertSeries([0., 0., 0.], mask.get("sym").toArray(), "isna sym nonempty");
		var withEmpty = DataFrame.fromColumns([
			"x" => Np.asarray([1., 2., 3.])
		], null, ["x"]).assignStr("sym", ["A", "", "C"]);
		var mask2 = FrameNa.isna(withEmpty);
		assertSeries([0., 1., 0.], mask2.get("sym").toArray(), "isna empty str");
		var dropped2 = FrameNa.dropna(withEmpty);
		Assert.equals(2, dropped2.nrows());
		Assert.same(["A", "C"], dropped2.strValuesOf("sym"));
	}

	public function testCorrSkipsStr() {
		var df = DataFrame.fromColumns([
			"a" => Np.asarray([1., 2., 3.]),
			"b" => Np.asarray([2., 4., 6.])
		], null, ["a", "b"]).assignStr("sym", ["A", "B", "C"]);
		var c = Pd.corr(df);
		Assert.same(["a", "b"], c.columns());
		Assert.isFalse(c.hasStrColumn("sym"));
		Assert.isTrue(approxEq(1., c.get("a").getFlat(0)));
	}

	public function testResamplePreservesStr() {
		var df = DataFrame.fromColumns([
			"close" => Np.asarray([1., 2., 3., 4.])
		], Index.fromFloats([0., 1., 2., 3.]), ["close"])
			.assignStr("sym", ["A", "A", "B", "B"]);
		var out = Pd.resample(df, "2");
		Assert.equals(2, out.nrows());
		Assert.same(["A", "B"], out.strValuesOf("sym"));
		assertSeries([2., 4.], out.get("close").toArray(), "last close");
	}

	public function testCsvParseStringColumn() {
		var df = Pd.parseCsv("t,sym,x\n1,AAPL,10\n2,MSFT,20\n");
		Assert.isTrue(df.hasStrColumn("sym"));
		Assert.same(["AAPL", "MSFT"], df.strValuesOf("sym"));
		assertSeries([1., 2.], df.get("t").toArray(), "t");
		assertSeries([10., 20.], df.get("x").toArray(), "x");
	}

	public function testParquetFromObjectsStringColumn() {
		var df = PdParquet.fromObjects([
			{ t: 1, sym: "AAPL", x: 10 },
			{ t: 2, sym: "MSFT", x: 20 }
		]);
		Assert.isTrue(df.hasStrColumn("sym"));
		Assert.same(["AAPL", "MSFT"], df.strValuesOf("sym"));
		assertSeries([10., 20.], df.get("x").toArray(), "x");
	}

	public function testMergeAsofPreservesStr() {
		var left = DataFrame.fromColumns([
			"time" => Np.asarray([1., 2., 3., 4.]),
			"px" => Np.asarray([0., 0., 0., 0.])
		], Index.fromFloats([1., 2., 3., 4.]), ["time", "px"])
			.assignStr("sym", ["A", "A", "A", "A"]);
		var right = DataFrame.fromColumns([
			"time" => Np.asarray([2., 4.]),
			"fact" => Np.asarray([10., 20.])
		], null, ["time", "fact"]).assignStr("src", ["edgar", "edgar"]);
		var out = MergeAsof.merge(left, right, "time");
		Assert.same(["A", "A", "A", "A"], out.strValuesOf("sym"));
		Assert.same(["", "edgar", "edgar", "edgar"], out.strValuesOf("src"));
		assertSeries([Math.NaN, 10., 10., 20.], out.get("fact").toArray(), "asof");
	}

	public function testResetIndexThenConcatRoundTrip() {
		var g = Pd.groupbyKeysAgg(withSym([1., 1., 2.], [10., 20., 40.], ["AAPL", "MSFT", "AAPL"]), ["t", "sym"], "sum", true);
		var flat = g.resetIndex();
		Assert.isTrue(flat.hasStrColumn("sym"));
		var more = withSym([3.], [50.], ["GOOG"]);
		var stacked = Pd.concat([flat, more]);
		Assert.same(["AAPL", "MSFT", "AAPL", "GOOG"], stacked.strValuesOf("sym"));
		assertSeries([1., 1., 2., 3.], stacked.get("t").toArray(), "t");
	}

	public function testAssignStrOverwritesF64SameName() {
		var df = DataFrame.fromColumns(["sym" => Np.asarray([1., 2.])], null, ["sym"]);
		var out = df.assignStr("sym", ["A", "B"]);
		Assert.isTrue(out.hasStrColumn("sym"));
		Assert.equals(0, out.f64Columns().length);
		Assert.same(["A", "B"], out.strValuesOf("sym"));
	}

	public function testXsPreservesExtraStr() {
		var mi = musescript.dataframe.MultiIndex.fromArrays([1., 1., 2.], [0., 1., 0.], ["t", "sec"]);
		var df = DataFrame.fromColumns(
			["x" => Np.asarray([10., 20., 30.])],
			Index.fromMulti(mi),
			["x"],
			["note" => ["a", "b", "c"]],
			["note"]
		);
		var cross = df.xs(1., 0);
		Assert.equals(2, cross.nrows());
		Assert.same(["a", "b"], cross.strValuesOf("note"));
	}
}
