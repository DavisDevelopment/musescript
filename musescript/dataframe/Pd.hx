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
 * Engine eligibility: Interp N | JS B (`pd_*`) | WASM H/U | VM H/U (`VmPdEligibility`)
 * Columns are NdArray F64; compose via `NdBridge` / `PdBridge`.
 * IO (`read_csv` / `read_parquet`) is grant-gated — null grants throw IoDenied.
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

	/** Grant-gated Parquet ingest (Node + optional hyparquet). Null grants → IoDenied. */
	public static inline function readParquet(?grants:Null<IoGrant>, path:String):DataFrame
		return PdParquet.readParquet(grants, path);

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
	 * Cross-section ranks: wide F64 columns → rank across columns per row.
	 * Str sidecars pass through. Trading path: factor panel → xs_rank → bags.
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

	/**
	 * Multi-key agg. Default `asIndex=false` keeps M3 column shape; `true` → MultiIndex
	 * on the row Index (all by-cols as levels; F64 and/or Str).
	 */
	public static inline function groupbyKeysAgg(
		df:DataFrame,
		by:Array<String>,
		?fn:String = "mean",
		?asIndex:Bool = false
	):DataFrame
		return GroupBy.createKeys(df, by).agg(fn, asIndex);

	public static inline function multiIndex(
		level0:Array<Float>,
		level1:Array<Float>,
		?names:Array<String>
	):AnyIndex
		return Index.multiFromArrays(level0, level1, names);

	public static inline function multiIndexStr(
		level0:Array<String>,
		level1:Array<String>,
		?names:Array<String>
	):AnyIndex
		return Index.multiFromArraysStr(level0, level1, names);

	public static inline function multiIndexLevels(
		levels:Array<MultiLevel>,
		?names:Array<String>
	):AnyIndex
		return Index.multiFromLevels(levels, names);

	public static inline function resetIndex(df:DataFrame, ?drop:Bool = false, ?name:String = "index"):DataFrame
		return df.resetIndex(drop, name);

	public static inline function xs(df:DataFrame, key:Float, ?level:Int = 0):DataFrame
		return df.xs(key, level);

	public static inline function xsStr(df:DataFrame, key:String, ?level:Int = 0):DataFrame
		return df.xsStr(key, level);

	public static inline function getLevelValues(df:DataFrame, ?level:Int = 0):Array<Float>
		return df.getLevelValues(level);

	public static inline function getLevelValuesStr(df:DataFrame, ?level:Int = 0):Array<String>
		return df.getLevelValuesStr(level);

	public static inline function indexNlevels(idx:AnyIndex):Int
		return Index.nlevelsOf(idx);

	/** Factorize F64 values → codes + uniques (`dropNa` → −1 for NaN). */
	public static inline function factorizeF64(values:Array<Float>, ?dropNa:Bool = true):FactorizeResult
		return Factorize.f64(values, dropNa);

	/** Factorize Str values → codes + uniques. */
	public static inline function factorizeStr(values:Array<String>, ?dropNa:Bool = true):FactorizeResult
		return Factorize.str(values, dropNa);

	/** Factorize a DataFrame column (Str sidecar or F64). */
	public static function factorizeCol(df:DataFrame, col:String, ?dropNa:Bool = true):FactorizeResult {
		if (df == null || col == null || col == "")
			return Factorize.f64([], dropNa);
		if (df.hasStrColumn(col)) {
			var s = df.strValuesOf(col);
			return Factorize.str(s != null ? s : [], dropNa);
		}
		var c = df.valuesOf(col);
		return Factorize.f64Nd(c, dropNa);
	}

	/** MultiIndex codes (one Int array per level). */
	public static function indexCodes(idx:AnyIndex):Array<Array<Int>> {
		var mi = Index.asMulti(idx);
		if (mi == null) return [];
		return mi.codes();
	}

	/** MultiIndex unique levels (pandas `.levels`). */
	public static function indexLevels(idx:AnyIndex):Array<MultiLevel> {
		var mi = Index.asMulti(idx);
		if (mi == null) return [];
		return mi.uniqueLevels();
	}

	public static inline function multiIndexFromCodes(
		uniques:Array<MultiLevel>,
		codes:Array<Array<Int>>,
		?names:Array<String>
	):AnyIndex
		return Index.fromMulti(MultiIndex.fromCodes(uniques, codes, names));

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

	// --- M4: resample + 1-D rank (WASM-native path for packed vec) ---

	/**
	 * Resample / down-sample. Rules: `"5"`/`"5B"` bar count; `"1h"`/`"5m"`/`"1000ms"` on F64 time index.
	 * Default `how="ohlcv"` (open first, high max, low min, close last, volume sum).
	 */
	public static inline function resample(df:DataFrame, rule:String, ?how:String = "ohlcv"):DataFrame
		return Resample.agg(df, rule, how);

	/**
	 * Average-tie 1-D rank on a packed numeric vector (not a DataFrame).
	 * WASM **N** for len ≤ 64 via `$vec_rank` / `$vec_rank_pct` — see docs/WASM_PD.md.
	 * Prefer this over `pd_xs_rank` when scores already live in scratch / NdArray.
	 */
	public static function rank1d(data:NdArrayF64, ?pct:Bool = false, ?ascending:Bool = true):NdArrayF64
		return GroupBy.rank1d(data, pct, ascending);
}
