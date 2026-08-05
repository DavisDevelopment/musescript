package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.Align;
import musescript.dataframe.DataFrame;
import musescript.dataframe.Factorize;
import musescript.dataframe.Index;
import musescript.dataframe.IndexF64;
import musescript.dataframe.IndexStr;
import musescript.dataframe.MultiIndex;
import musescript.dataframe.MultiLevel;
import musescript.dataframe.Pd;
import musescript.builtins.MuseHost;
import musescript.builtins.PdBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.compile.WasmPdEligibility;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;

/**
 * muse.pd MultiIndex — F64 / Str / N-level construct, groupby as_index, xs, reset_index,
 * codes / factorize.
 */
class TestPdMultiIndex extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] got ${actual[i]} want ${expected[i]}');
	}

	function factorLong():DataFrame {
		return DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 1., 2.]),
			"sec" => Np.asarray([0., 0., 1., 0.]),
			"x" => Np.asarray([10., 20., 30., 40.])
		], null, ["t", "sec", "x"]);
	}

	function factorLongStr():DataFrame {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 1., 2.]),
			"x" => Np.asarray([10., 20., 30., 40.])
		], null, ["t", "x"]);
		return df.assignStr("sym", ["AAPL", "AAPL", "MSFT", "AAPL"]);
	}

	public function testConstructFromArrays() {
		var mi = MultiIndex.fromArrays([1., 1., 2.], [0., 1., 0.], ["t", "sec"]);
		Assert.equals(3, mi.length);
		Assert.equals(2, mi.nlevels);
		Assert.same(["t", "sec"], mi.names());
		Assert.equals("multi", Index.kindOf(Index.fromMulti(mi)));
		Assert.equals(2, Index.nlevelsOf(Index.fromMulti(mi)));
		assertSeries([1., 1., 2.], mi.levelValues(0), "L0");
		assertSeries([0., 1., 0.], mi.levelValues(1), "L1");
	}

	public function testConstructFromArraysStr() {
		var mi = MultiIndex.fromArraysStr(["a", "a", "b"], ["tech", "fin", "tech"], ["sym", "sec"]);
		Assert.equals(3, mi.length);
		Assert.equals(2, mi.nlevels);
		Assert.equals("str", mi.levelKind(0));
		Assert.equals("str", mi.levelKind(1));
		Assert.same(["a", "a", "b"], mi.levelValuesStr(0));
		Assert.same(["tech", "fin", "tech"], mi.levelValuesStr(1));
		Assert.equals("multi", Index.kindOf(Index.fromMulti(mi)));
	}

	public function testConstructMixedAndNLevels() {
		var mi = MultiIndex.fromLevels([
			MultiLevel.F64(IndexF64.fromArray([1., 1., 2.])),
			MultiLevel.Str(IndexStr.fromArray(["AAPL", "MSFT", "AAPL"])),
			MultiLevel.F64(IndexF64.fromArray([0., 1., 0.]))
		], ["t", "sym", "sec"]);
		Assert.equals(3, mi.nlevels);
		Assert.equals(3, mi.length);
		Assert.equals("f64", mi.levelKind(0));
		Assert.equals("str", mi.levelKind(1));
		Assert.equals("f64", mi.levelKind(2));
		assertSeries([1., 1., 2.], mi.levelValues(0), "L0");
		Assert.same(["AAPL", "MSFT", "AAPL"], mi.levelValuesStr(1));
		var idx = Pd.multiIndexLevels([
			MultiLevel.F64(IndexF64.fromArray([1., 2.])),
			MultiLevel.Str(IndexStr.fromArray(["X", "Y"]))
		], ["t", "sym"]);
		Assert.equals(2, Pd.indexNlevels(idx));
	}

	public function testPdMultiIndexFacade() {
		var idx = Pd.multiIndex([10., 20.], [1., 2.], ["a", "b"]);
		Assert.equals("multi", Index.kindOf(idx));
		Assert.equals(2, Pd.indexNlevels(idx));
		var sidx = Pd.multiIndexStr(["a", "b"], ["x", "y"], ["s0", "s1"]);
		Assert.equals("multi", Index.kindOf(sidx));
		Assert.equals(2, Pd.indexNlevels(sidx));
	}

	public function testGroupbyAsIndexFalseCompat() {
		// M3 shape: keys as columns + range Index (default)
		var g = Pd.groupbyKeysAgg(factorLong(), ["t", "sec"], "mean");
		Assert.equals(3, g.nrows());
		Assert.isTrue(g.hasColumn("t") && g.hasColumn("sec") && g.hasColumn("x"));
		Assert.equals("f64", Index.kindOf(g.index));
		assertSeries([15., 30., 40.], g.get("x").toArray(), "mean");
	}

	public function testGroupbyAsIndexTrueMulti() {
		var g = Pd.groupbyKeysAgg(factorLong(), ["t", "sec"], "mean", true);
		Assert.equals(3, g.nrows());
		Assert.isFalse(g.hasColumn("t"));
		Assert.isFalse(g.hasColumn("sec"));
		Assert.isTrue(g.hasColumn("x"));
		Assert.equals("multi", Index.kindOf(g.index));
		Assert.equals(2, Index.nlevelsOf(g.index));
		assertSeries([15., 30., 40.], g.get("x").toArray(), "mean");
		assertSeries([1., 1., 2.], g.getLevelValues(0), "L0");
		assertSeries([0., 1., 0.], g.getLevelValues(1), "L1");
	}

	public function testGroupbyAsIndexTrueStr() {
		var g = Pd.groupbyKeysAgg(factorLongStr(), ["t", "sym"], "mean", true);
		Assert.equals(3, g.nrows());
		Assert.isFalse(g.hasColumn("t"));
		Assert.isFalse(g.hasColumn("sym"));
		Assert.isTrue(g.hasColumn("x"));
		Assert.equals("multi", Index.kindOf(g.index));
		Assert.equals(2, Index.nlevelsOf(g.index));
		assertSeries([15., 30., 40.], g.get("x").toArray(), "mean");
		assertSeries([1., 1., 2.], g.getLevelValues(0), "L0 t");
		Assert.same(["AAPL", "MSFT", "AAPL"], g.getLevelValuesStr(1));
	}

	public function testGroupbyAsIndexFalseStrKeys() {
		var g = Pd.groupbyKeysAgg(factorLongStr(), ["t", "sym"], "sum", false);
		Assert.equals(3, g.nrows());
		Assert.isTrue(g.hasColumn("t") && g.hasStrColumn("sym") && g.hasColumn("x"));
		Assert.same(["AAPL", "MSFT", "AAPL"], g.strValuesOf("sym"));
		assertSeries([30., 30., 40.], g.get("x").toArray(), "sum");
	}

	public function testXsByLevel() {
		var g = Pd.groupbyKeysAgg(factorLong(), ["t", "sec"], "mean", true);
		var cross = g.xs(1., 0); // all rows with t==1
		Assert.equals(2, cross.nrows());
		Assert.equals("f64", Index.kindOf(cross.index));
		assertSeries([0., 1.], Index.asF64(cross.index).toArray(), "remaining sec");
		assertSeries([15., 30.], cross.get("x").toArray(), "xs vals");
		var sec0 = g.xs(0., 1);
		Assert.equals(2, sec0.nrows());
		assertSeries([1., 2.], Index.asF64(sec0.index).toArray(), "remaining t");
		assertSeries([15., 40.], sec0.get("x").toArray(), "sec0");
	}

	public function testXsStr() {
		var g = Pd.groupbyKeysAgg(factorLongStr(), ["t", "sym"], "mean", true);
		var aapl = g.xsStr("AAPL", 1);
		Assert.equals(2, aapl.nrows());
		Assert.equals("f64", Index.kindOf(aapl.index));
		assertSeries([1., 2.], Index.asF64(aapl.index).toArray(), "remaining t");
		assertSeries([15., 40.], aapl.get("x").toArray(), "aapl");
	}

	public function testResetIndexMulti() {
		var g = Pd.groupbyKeysAgg(factorLong(), ["t", "sec"], "sum", true);
		var r = g.resetIndex();
		Assert.equals("f64", Index.kindOf(r.index));
		Assert.isTrue(r.hasColumn("t") && r.hasColumn("sec") && r.hasColumn("x"));
		assertSeries([1., 1., 2.], r.get("t").toArray(), "t");
		assertSeries([0., 1., 0.], r.get("sec").toArray(), "sec");
		assertSeries([30., 30., 40.], r.get("x").toArray(), "sum");
		var dropped = g.resetIndex(true);
		Assert.isFalse(dropped.hasColumn("t"));
		Assert.equals(3, dropped.nrows());
	}

	public function testResetIndexMultiStr() {
		var g = Pd.groupbyKeysAgg(factorLongStr(), ["t", "sym"], "sum", true);
		var r = g.resetIndex();
		Assert.equals("f64", Index.kindOf(r.index));
		Assert.isTrue(r.hasColumn("t") && r.hasStrColumn("sym") && r.hasColumn("x"));
		assertSeries([1., 1., 2.], r.get("t").toArray(), "t");
		Assert.same(["AAPL", "MSFT", "AAPL"], r.strValuesOf("sym"));
		assertSeries([30., 30., 40.], r.get("x").toArray(), "sum");
	}

	public function testResetIndexF64() {
		var df = DataFrame.fromColumns([
			"v" => Np.asarray([1., 2., 3.])
		], Index.fromFloats([10., 20., 30.]), ["v"]);
		var r = Pd.resetIndex(df);
		Assert.isTrue(r.hasColumn("index"));
		assertSeries([10., 20., 30.], r.get("index").toArray(), "idx col");
	}

	public function testReindexMulti() {
		var mi = MultiIndex.fromArrays([1., 2.], [0., 1.], ["t", "sec"]);
		var df = DataFrame.fromColumns([
			"x" => Np.asarray([100., 200.])
		], Index.fromMulti(mi), ["x"]);
		var target = Index.multiFromArrays([2., 1., 9.], [1., 0., 0.], ["t", "sec"]);
		var out = Align.reindex(df, target);
		assertSeries([200., 100., Math.NaN], out.get("x").toArray(), "reindex");
	}

	public function testSliceTakePreserveMulti() {
		var mi = MultiIndex.fromArrays([1., 1., 2.], [0., 1., 0.], ["t", "s"]);
		var df = DataFrame.fromColumns([
			"x" => Np.asarray([10., 20., 30.])
		], Index.fromMulti(mi), ["x"]);
		var h = df.head(2);
		Assert.equals("multi", Index.kindOf(h.index));
		Assert.equals(2, h.nrows());
		assertSeries([1., 1.], h.getLevelValues(0), "head L0");
	}

	public function testBuiltinsAndHostLower() {
		Assert.equals("pd_reset_index", MuseHost.resolveFlat("pd", "reset_index"));
		Assert.equals("pd_xs", MuseHost.resolveFlat("pd", "xs"));
		Assert.equals("pd_get_level_values", MuseHost.resolveFlat("pd", "get_level_values"));
		Assert.equals("pd_get_level_values_str", MuseHost.resolveFlat("pd", "get_level_values_str"));
		Assert.equals("pd_index_nlevels", MuseHost.resolveFlat("pd", "index_nlevels"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_multi_index"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_xs"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_get_level_values_str"));

		var idx = PdBuiltins.multiIndexOf([1, 2], [0, 1], ["t", "sec"]);
		Assert.equals(2, PdBuiltins.indexNlevelsOf(idx));
		var sidx = PdBuiltins.multiIndexOf(["a", "b"], ["x", "y"], ["s0", "s1"]);
		Assert.equals(2, PdBuiltins.indexNlevelsOf(sidx));

		var src = '
			strategy S {
			  onBar {
			    var mi = muse.pd.multi_index([1, 2], [0, 1], ["t", "sec"])
			    var n = muse.pd.index_nlevels(mi)
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_multi_index(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_index_nlevels(") >= 0, printed);
	}

	public function testFromFrameAndKeyRows() {
		var df = factorLong();
		var mi = MultiIndex.fromFrame(df, ["t", "sec"]);
		Assert.equals(4, mi.length);
		assertSeries([1., 1., 1., 2.], mi.levelValues(0), "frame L0");
		var rows = [[1., 0.], [2., 1.]];
		var fromKeys = MultiIndex.fromKeyRows(rows, ["t", "sec"]);
		Assert.equals(2, fromKeys.length);
		Assert.isTrue(fromKeys.equals(MultiIndex.fromArrays([1., 2.], [0., 1.], ["t", "sec"])));
		var withStr = MultiIndex.fromFrameLevels(factorLongStr(), ["t", "sym"]);
		Assert.equals(4, withStr.length);
		Assert.equals("str", withStr.levelKind(1));
		Assert.same(["AAPL", "AAPL", "MSFT", "AAPL"], withStr.levelValuesStr(1));
	}

	public function testThreeLevelAsIndex() {
		var df = DataFrame.fromColumns([
			"t" => Np.asarray([1., 1., 2.]),
			"sec" => Np.asarray([0., 1., 0.]),
			"bucket" => Np.asarray([10., 10., 20.]),
			"x" => Np.asarray([1., 2., 3.])
		], null, ["t", "sec", "bucket", "x"]);
		var g = Pd.groupbyKeysAgg(df, ["t", "sec", "bucket"], "sum", true);
		Assert.equals(3, g.nrows());
		Assert.equals("multi", Index.kindOf(g.index));
		Assert.equals(3, Index.nlevelsOf(g.index));
		Assert.isFalse(g.hasColumn("t"));
		Assert.isFalse(g.hasColumn("bucket"));
		assertSeries([1., 2., 3.], g.get("x").toArray(), "sum");
	}

	public function testFactorizeF64() {
		var fr = Factorize.f64([1., 2., 1., Math.NaN, 2.], true);
		Assert.same([0, 1, 0, -1, 1], fr.codes);
		assertSeries([1., 2.], fr.uniquesAsFloats(), "uniques");
		Assert.equals("f64", fr.kind());
		var keep = Factorize.f64([1., Math.NaN, 1.], false);
		Assert.equals(2, keep.nUniques());
		Assert.isTrue(keep.codes[1] >= 0, "NaN kept as unique");
	}

	public function testFactorizeStr() {
		var fr = Factorize.str(["AAPL", "MSFT", "AAPL", ""]);
		Assert.same([0, 1, 0, 2], fr.codes);
		Assert.same(["AAPL", "MSFT", ""], fr.uniquesAsStrings());
		Assert.equals("str", fr.kind());
	}

	public function testFactorizeCol() {
		var df = factorLongStr();
		var fr = Pd.factorizeCol(df, "sym");
		Assert.same([0, 0, 1, 0], fr.codes);
		Assert.same(["AAPL", "MSFT"], fr.uniquesAsStrings());
		var frT = Pd.factorizeCol(df, "t");
		Assert.same([0, 0, 0, 1], frT.codes);
		assertSeries([1., 2.], frT.uniquesAsFloats(), "t uniques");
	}

	public function testMultiIndexCodes() {
		var mi = MultiIndex.fromArrays([1., 1., 2., 1.], [0., 1., 0., 0.], ["t", "sec"]);
		var codes = mi.codes();
		Assert.equals(2, codes.length);
		Assert.same([0, 0, 1, 0], codes[0]);
		Assert.same([0, 1, 0, 0], codes[1]);
		var u0 = mi.uniqueLevelAt(0);
		Assert.isTrue(u0 != null);
		switch (u0) {
			case F64(i): assertSeries([1., 2.], i.toArray(), "u0");
			default: Assert.fail("want F64");
		}
		var fromC = MultiIndex.fromCodes(mi.uniqueLevels(), mi.codes(), ["t", "sec"]);
		Assert.isTrue(fromC.isCodesPrimary());
		Assert.isTrue(fromC.equals(mi));
		assertSeries([1., 1., 2., 1.], fromC.levelValues(0), "densify L0");
		// xs via codes path before densify side-effects: rebuild fresh
		var fromC2 = MultiIndex.fromCodes(mi.uniqueLevels(), mi.codes(), ["t", "sec"]);
		Assert.isTrue(fromC2.isCodesPrimary());
		Assert.same([0, 1, 3], fromC2.xsPositions(1., 0));
	}

	public function testFromFrameCodesAndCompact() {
		var df = factorLongStr();
		var mi = MultiIndex.fromFrameCodes(df, ["t", "sym"]);
		Assert.isTrue(mi.isCodesPrimary());
		Assert.equals(4, mi.length);
		Assert.equals(2, mi.nlevels);
		Assert.same(["AAPL", "AAPL", "MSFT", "AAPL"], mi.levelValuesStr(1));
		var dense = MultiIndex.fromFrameLevels(df, ["t", "sym"]);
		Assert.isTrue(mi.toCodesForm().equals(dense.toCodesForm()));
	}

	public function testPdFactorizeFlats() {
		Assert.equals("pd_factorize", MuseHost.resolveFlat("pd", "factorize"));
		Assert.equals("pd_index_codes", MuseHost.resolveFlat("pd", "index_codes"));
		Assert.equals("pd_index_levels", MuseHost.resolveFlat("pd", "index_levels"));
		Assert.equals("pd_multi_index_codes", MuseHost.resolveFlat("pd", "multi_index_codes"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_factorize"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_multi_index_codes"));

		var bag:Dynamic = PdBuiltins.factorizeOf([1, 2, 1, Math.NaN]);
		Assert.same([0., 1., 0., -1.], bag.codes);
		Assert.same([1., 2.], bag.uniques);
		Assert.equals("f64", bag.kind);

		var sbag:Dynamic = PdBuiltins.factorizeOf(["a", "b", "a"]);
		Assert.same([0., 1., 0.], sbag.codes);
		Assert.same(["a", "b"], sbag.uniques);

		var mi = MultiIndex.fromArrays([1., 1., 2.], [0., 1., 0.], ["t", "sec"]);
		var idx = Index.fromMulti(mi);
		var codes = PdBuiltins.indexCodesOf(idx);
		Assert.same([0., 0., 1.], codes[0]);
		Assert.same([0., 1., 0.], codes[1]);
		var lv0:Array<Float> = cast PdBuiltins.indexLevelsOf(idx, 0);
		assertSeries([1., 2.], lv0, "levels0");

		var rebuilt = PdBuiltins.multiIndexCodesOf([[1., 2.], [0., 1.]], [[0, 0, 1], [0, 1, 0]], ["t", "sec"]);
		Assert.equals(2, PdBuiltins.indexNlevelsOf(rebuilt));
		Assert.isTrue(Index.equals(rebuilt, idx));

		var src = '
			strategy S {
			  onBar {
			    var fz = muse.pd.factorize([1, 2, 1])
			    var mi = muse.pd.multi_index_codes([[1, 2], [0, 1]], [[0, 0, 1], [0, 1, 0]], ["t", "sec"])
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_factorize(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_multi_index_codes(") >= 0, printed);
	}
}
