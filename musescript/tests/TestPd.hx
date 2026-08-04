package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.DataFrame;
import musescript.dataframe.Index;
import musescript.dataframe.IndexF64;
import musescript.dataframe.IndexStr;
import musescript.dataframe.Pd;
import musescript.dataframe.Series;
import musescript.dataframe.bridge.PdBridge;
import musescript.builtins.PdBuiltins;
import musescript.builtins.MuseHost;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.interp.MuseInterp;
import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;
import musescript.types.BuiltinSigs;
import musescript.types.MuseType;
import musescript.types.MuseTypes;

/**
 * muse.pd M0 — Index / Series / DataFrame construct+select, bridges, host spine.
 */
class TestPd extends Test {
	public function testIndexF64AndStr() {
		var r = IndexF64.range(4);
		Assert.equals(4, r.length);
		Assert.equals(0.0, r.get(0));
		Assert.equals(3.0, r.get(3));
		var sliced = r.slice(1, 3);
		Assert.same([1.0, 2.0], sliced.toArray());

		var s = IndexStr.fromArray(["AAPL", "MSFT", "AAPL"]);
		Assert.equals(3, s.length);
		Assert.equals("MSFT", s.get(1));
		Assert.equals(2, s.take([2, 0]).length);
		Assert.equals("AAPL", s.take([2, 0]).get(0));
	}

	public function testSeriesConstructAndSharedValues() {
		var vals = Np.asarray([1.0, 2.0, 3.0]);
		var ser = Series.create(vals, Index.range(3), "close");
		Assert.equals("close", ser.name);
		Assert.equals(3, ser.length);
		Assert.equals(2.0, ser.getFlat(1));
		// Shared buffer mutate-through
		ser.setFlat(1, 9.0);
		Assert.equals(9.0, vals.getFlat(1));
		Assert.same([1.0, 9.0, 3.0], ser.head(5).toArray());
	}

	public function testDataFrameFromColumnsSelectShape() {
		var map = new Map<String, NdArrayF64>();
		map.set("close", Np.asarray([10.0, 11.0, 12.0]));
		map.set("volume", Np.asarray([100.0, 200.0, 300.0]));
		var df = DataFrame.fromColumns(map, Index.fromFloats([1.0, 2.0, 3.0]), ["close", "volume"]);
		Assert.same([3, 2], df.shape());
		Assert.same(["close", "volume"], df.columns());
		Assert.equals(11.0, df.get("close").getFlat(1));
		// Column Series shares buffer
		df.get("close").setFlat(0, 99.0);
		Assert.equals(99.0, df.valuesOf("close").getFlat(0));

		var sub = df.select(["volume"]);
		Assert.equals(1, sub.ncols());
		Assert.equals(200.0, sub.get("volume").getFlat(1));

		var copied = df.copy();
		copied.get("volume").setFlat(0, -1.0);
		Assert.equals(100.0, df.valuesOf("volume").getFlat(0)); // original owned-copy independent
	}

	public function testFromNdArrayAndToNdArray() {
		var mat = Np.asarray2d([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]);
		var df = Pd.fromNdArray(mat, null, ["a", "b"]);
		Assert.same([3, 2], df.shape());
		Assert.equals(4.0, df.get("b").getFlat(1));
		var back = df.toNdArray();
		Assert.equals(5.0, back.get2(2, 0));
		Assert.equals(6.0, back.get2(2, 1));
	}

	public function testAssignDropHeadIloc() {
		var map = new Map<String, NdArrayF64>();
		map.set("x", Np.asarray([1.0, 2.0, 3.0, 4.0]));
		var df = DataFrame.fromColumns(map, null, ["x"]);
		df = df.assign("y", Np.asarray([10.0, 20.0, 30.0, 40.0]));
		Assert.equals(2, df.ncols());
		df = df.drop(["x"]);
		Assert.same(["y"], df.columns());
		Assert.same([10.0, 20.0], df.head(2).get("y").toArray());
		Assert.same([40.0, 20.0], df.iloc([3, 1]).get("y").toArray());
	}

	public function testPdBridgeBarsAndBarColumn() {
		var bars:Array<Bar> = [
			{open: 1, high: 2, low: 0.5, close: 1.5, volume: 10, time: 100.0, index: 0, data: ["rev" => 7.0]},
			{open: 1.5, high: 2.5, low: 1.0, close: 2.0, volume: 20, time: 200.0, index: 1, data: ["rev" => 8.0]}
		];
		var ohlcv = PdBridge.fromBars(bars);
		Assert.same(["open", "high", "low", "close", "volume"], ohlcv.columns());
		Assert.equals(2.0, ohlcv.get("close").getFlat(1));
		var idx = Index.asF64(ohlcv.index);
		Assert.notNull(idx);
		Assert.equals(100.0, idx.get(0));

		var rev = PdBridge.fromBarDataColumn(bars, "rev");
		Assert.equals("rev", rev.name);
		Assert.same([7.0, 8.0], rev.toArray());
	}

	public function testPdBridgePanelWide() {
		var panel = PanelFeed.synthetic(3, 5, 1);
		var closes = PdBridge.fromPanelFeed(panel, ["close"]);
		Assert.equals(panel.symbols.length, closes.ncols());
		Assert.equals(5, closes.nrows());
		Assert.isTrue(closes.hasColumn(panel.symbols[0]));

		var multi = PdBridge.fromPanelFeed(panel, ["close", "volume"]);
		Assert.equals(panel.symbols.length * 2, multi.ncols());
		Assert.isTrue(multi.hasColumn("close@" + panel.symbols[0]));
	}

	public function testNoDynamicOnTypedApi() {
		// Compile-time typed surface — Series.values is NdArrayF64, not Dynamic.
		var s:Series = Pd.seriesFromArray([1.0, 2.0], null, "x");
		var a:NdArrayF64 = s.values;
		Assert.equals(2, a.size);
		var df:DataFrame = Pd.fromColumns(["a" => a], null, ["a"]);
		var cols:Array<String> = df.columns();
		Assert.equals(1, cols.length);
	}

	public function testBuiltinSigsAndTypes() {
		Assert.isTrue(BuiltinSigs.get("pd_from_columns") != null);
		Assert.isTrue(BuiltinSigs.get("pd_get") != null);
		Assert.equals("DataFrame", MuseTypes.toString(TDataFrame));
		Assert.equals("PdSeries", MuseTypes.toString(TPdSeries));
		Assert.equals("Index", MuseTypes.toString(TIndex));
		Assert.notEquals("Series", MuseTypes.toString(TPdSeries));
		Assert.equals(TPdSeries, MuseTypes.parseName("PdSeries"));
	}

	public function testMuseHostFlatResolveAndLower() {
		Assert.equals("pd_from_columns", MuseHost.resolveFlat("pd", "from_columns"));
		Assert.equals("pd_get", MuseHost.resolveFlat("dataframe", "get"));
		Assert.equals("pd_from_panel", MuseHost.resolveFlat("pd", "from_panel"));

		var src = '
			strategy S {
			  onBar {
			    var df = muse.pd.from_columns({close: [1, 2, 3], volume: [4, 5, 6]})
			    var c = muse.pd.get(df, "close")
			    var n = muse.pd.nrows(df)
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("pd_from_columns(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_get(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_nrows(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.pd") < 0, printed);
	}

	public function testMuseInterpPdSmoke() {
		var src = '
			@strategy("pd-smoke")
			@on(bar) {
				var df = muse.pd.from_columns({close: [1, 2, 3], volume: [10, 20, 30]});
				var c = muse.pd.get(df, "close");
				var n = muse.pd.nrows(df);
				var m = muse.pd.ncols(df);
				var s = muse.pd.series_values(c);
				var total = muse.np.sum(s);
				if (n == 3 && m == 2 && total == 6 && muse.pd.series_length(c) == 3) long();
			}
		';
		var bars = [for (i in 0...3) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testMuseInterpSelectAndNdArray() {
		var src = '
			@strategy("pd-select")
			@on(bar) {
				var mat = muse.np.asarray([[1, 2], [3, 4], [5, 6]]);
				var df = muse.pd.from_ndarray(mat, null, ["a", "b"]);
				var sub = muse.pd.select(df, ["b"]);
				var col = muse.pd.get(sub, "b");
				var ok = muse.pd.nrows(df) == 3 && muse.np.sum(muse.pd.series_values(col)) == 12;
				if (ok) long();
			}
		';
		var bars:Array<Bar> = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testPdBuiltinsObjectColumns() {
		var df = PdBuiltins.fromColumns({close: [1, 2], open: [0.5, 1.5]}, null, ["open", "close"]);
		Assert.same(["open", "close"], df.columns());
		Assert.equals(0.5, df.get("open").getFlat(0));
		Assert.equals(2.0, PdBuiltins.nrowsOf(df));
	}

	public function testMergeAsofIsAvailable() {
		var left = DataFrame.fromColumns([
			"time" => Np.asarray([1.0, 2.0]),
			"px" => Np.asarray([0.0, 0.0])
		], null, ["time", "px"]);
		var right = DataFrame.fromColumns([
			"time" => Np.asarray([1.0]),
			"fact" => Np.asarray([5.0])
		], null, ["time", "fact"]);
		var out = Pd.mergeAsof(left, right, "time");
		Assert.equals(5.0, out.get("fact").getFlat(0));
		Assert.equals(5.0, out.get("fact").getFlat(1));
	}
}
