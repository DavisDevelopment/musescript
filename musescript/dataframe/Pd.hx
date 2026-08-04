package musescript.dataframe;

import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;
import musescript.harness.PanelFeed;
import musescript.harness.Bar;
import musescript.dataframe.bridge.PdBridge;
import musescript.io.IoGrant;

/**
 * Haxe `pd.*` facade — trading-critical dataframe feel, zero Dynamic on typed API.
 *
 * Engine eligibility: Interp N | JS B (`pd_*`) | WASM H/U | VM U
 * Columns are NdArray F64; compose via `NdBridge` / `PdBridge`.
 * IO (`read_csv`) is grant-gated — null grants throw IoDenied.
 */
class Pd {
	public static inline function series(data:NdArrayF64, ?index:AnyIndex, ?name:String):Series
		return Series.create(data, index, name);

	public static inline function seriesFromArray(data:Array<Float>, ?index:AnyIndex, ?name:String):Series
		return Series.fromArray(data, index, name);

	public static inline function fromColumns(
		columns:Map<String, NdArrayF64>,
		?index:AnyIndex,
		?columnOrder:Array<String>
	):DataFrame
		return DataFrame.fromColumns(columns, index, columnOrder);

	public static inline function fromNdArray(
		matrix:NdArrayF64,
		?index:AnyIndex,
		?columns:Array<String>
	):DataFrame
		return DataFrame.fromNdArray(matrix, index, columns);

	public static inline function dataframe(
		columns:Map<String, NdArrayF64>,
		?index:AnyIndex,
		?columnOrder:Array<String>
	):DataFrame
		return fromColumns(columns, index, columnOrder);

	public static function empty(?nrows:Int = 0, ?columns:Array<String>):DataFrame {
		if (columns == null || columns.length == 0)
			return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		var n = nrows < 0 ? 0 : nrows;
		for (c in columns) map.set(c, Np.zeros([n]));
		return DataFrame.fromColumns(map, Index.range(n), columns);
	}

	public static inline function fromBarDataColumn(bars:Array<Bar>, key:String, ?name:String):Series
		return PdBridge.fromBarDataColumn(bars, key, name);

	public static inline function fromBars(bars:Array<Bar>):DataFrame
		return PdBridge.fromBars(bars);

	public static inline function fromPanelFeed(panel:PanelFeed, ?fields:Array<String>):DataFrame
		return PdBridge.fromPanelFeed(panel, fields);

	public static inline function indexRange(n:Int):AnyIndex return Index.range(n);
	public static inline function indexFloats(labels:Array<Float>):AnyIndex return Index.fromFloats(labels);
	public static inline function indexStrings(labels:Array<String>):AnyIndex return Index.fromStrings(labels);

	public static inline function reindex(df:DataFrame, newIndex:AnyIndex):DataFrame
		return Align.reindex(df, newIndex);

	public static inline function align(left:DataFrame, right:DataFrame, ?how:String = "outer")
		return Align.align(left, right, how);

	public static inline function join(
		left:DataFrame,
		right:DataFrame,
		on:String,
		?how:String = "left",
		?validate:Bool = false
	):DataFrame
		return Join.onColumn(left, right, on, how, validate);

	/**
	 * Last-known right row with `right[on] ≤ left[on]` (default `direction="backward"`).
	 * PIT: `allowLookahead=false` refuses forward/nearest.
	 */
	public static function mergeAsof(
		left:DataFrame,
		right:DataFrame,
		on:String,
		?by:String,
		?direction:String = "backward",
		?allowLookahead:Bool = false,
		?tolerance:Null<Float>
	):DataFrame
		return MergeAsof.merge(left, right, on, by, direction, allowLookahead, tolerance);

	public static inline function fillna(df:DataFrame, value:Float):DataFrame
		return FrameNa.fillna(df, value);

	public static inline function dropna(df:DataFrame, ?how:String = "any"):DataFrame
		return FrameNa.dropna(df, how);

	public static inline function isna(df:DataFrame):DataFrame
		return FrameNa.isna(df);

	public static inline function concat(frames:Array<DataFrame>):DataFrame
		return Concat.axis0(frames);

	public static inline function concatCols(left:DataFrame, right:DataFrame, ?rsuffix:String = "_r"):DataFrame
		return Concat.axis1(left, right, rsuffix);

	/** Grant-gated CSV ingest. Null grants → IoDenied. */
	public static inline function readCsv(?grants:Null<IoGrant>, path:String):DataFrame
		return PdCsv.readCsv(grants, path);

	public static inline function parseCsv(text:String):DataFrame
		return PdCsv.parse(text);

	// --- M2: groupby / rank / windows ---

	public static inline function groupby(df:DataFrame, by:String):GroupBy
		return GroupBy.create(df, by);

	public static inline function groupbyAgg(df:DataFrame, by:String, ?fn:String = "mean"):DataFrame
		return GroupBy.create(df, by).agg(fn);

	public static inline function groupbyTransform(df:DataFrame, by:String, ?fn:String = "mean"):DataFrame
		return GroupBy.create(df, by).transform(fn);

	public static inline function groupbyRank(df:DataFrame, by:String, ?pct:Bool = false):DataFrame
		return GroupBy.create(df, by).rank(pct);

	/** Global Series rank (average ties). */
	public static inline function rank(s:Series, ?pct:Bool = false, ?ascending:Bool = true):Series
		return s.rank(pct, ascending);

	/**
	 * Cross-section ranks: wide frame → rank across columns per row.
	 * Trading path: factor wide panel → xs_rank → bag / target_weight helpers.
	 */
	public static inline function xsRank(df:DataFrame, ?pct:Bool = false, ?ascending:Bool = true):DataFrame
		return GroupBy.xsRankFrame(df, pct, ascending);

	public static inline function shiftSeries(s:Series, ?periods:Int = 1):Series
		return FrameWindow.shiftSeries(s, periods);

	public static inline function shiftFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return FrameWindow.shiftFrame(df, periods);

	public static inline function diffSeries(s:Series, ?periods:Int = 1):Series
		return FrameWindow.diffSeries(s, periods);

	public static inline function diffFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return FrameWindow.diffFrame(df, periods);

	public static inline function pctChangeSeries(s:Series, ?periods:Int = 1):Series
		return FrameWindow.pctChangeSeries(s, periods);

	public static inline function pctChangeFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return FrameWindow.pctChangeFrame(df, periods);

	public static inline function rollingMeanSeries(s:Series, window:Int):Series
		return FrameWindow.rollingMeanSeries(s, window);

	public static inline function rollingMeanFrame(df:DataFrame, window:Int):DataFrame
		return FrameWindow.rollingMeanFrame(df, window);

	public static inline function rollingStdSeries(s:Series, window:Int, ?ddof:Int = 1):Series
		return FrameWindow.rollingStdSeries(s, window, ddof);

	public static inline function rollingStdFrame(df:DataFrame, window:Int, ?ddof:Int = 1):DataFrame
		return FrameWindow.rollingStdFrame(df, window, ddof);

	public static inline function ewmMeanSeries(s:Series, span:Int):Series
		return FrameWindow.ewmMeanSeries(s, span);

	public static inline function ewmMeanFrame(df:DataFrame, span:Int):DataFrame
		return FrameWindow.ewmMeanFrame(df, span);

	// --- M3: reshape / multi-key / corr ---

	public static inline function groupbyKeys(df:DataFrame, by:Array<String>):GroupBy
		return GroupBy.createKeys(df, by);

	public static inline function groupbyKeysAgg(df:DataFrame, by:Array<String>, ?fn:String = "mean"):DataFrame
		return GroupBy.createKeys(df, by).agg(fn);

	public static inline function pivot(df:DataFrame, index:String, columns:String, values:String):DataFrame
		return FrameReshape.pivot(df, index, columns, values);

	public static inline function melt(
		df:DataFrame,
		?idVars:Array<String>,
		?valueVars:Array<String>,
		?varName:String,
		?valueName:String
	):DataFrame
		return FrameReshape.melt(df, idVars, valueVars, varName, valueName);

	public static inline function corr(df:DataFrame):DataFrame
		return FrameCorr.corr(df);

	public static inline function cov(df:DataFrame, ?ddof:Int = 1):DataFrame
		return FrameCorr.cov(df, ddof);
}
