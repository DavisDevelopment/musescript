package musescript.builtins;

import musescript.dataframe.AnyIndex;
import musescript.dataframe.Align;
import musescript.dataframe.Concat;
import musescript.dataframe.DataFrame;
import musescript.dataframe.FrameCorr;
import musescript.dataframe.FrameNa;
import musescript.dataframe.FrameReshape;
import musescript.dataframe.FrameWindow;
import musescript.dataframe.GroupBy;
import musescript.dataframe.Index;
import musescript.dataframe.IndexF64;
import musescript.dataframe.Join;
import musescript.dataframe.MergeAsof;
import musescript.dataframe.Pd;
import musescript.dataframe.PdCsv;
import musescript.dataframe.Series;
import musescript.dataframe.bridge.PdBridge;
import musescript.harness.Bar;
import musescript.harness.PanelFeed;
import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;

/**
 * Muse install surface for `muse.pd` / `muse.dataframe` / flat `pd_*`.
 *
 * Engine eligibility: Interp N | JS B | WASM H/U | VM U
 * Dynamic only at this coercion boundary — typed callers use `Pd` / `DataFrame`.
 * Do not confuse with streaming Muse `TSeries`.
 */
class PdBuiltins {
	public static function install(vars:Map<String, Dynamic>, ?grantsOf:Void->Null<musescript.io.IoGrant>):Void {
		var g = grantsOf == null ? function() return null : grantsOf;
		for (k in FLAT_NAMES.keys()) vars.set(k, FLAT_NAMES.get(k));
		vars.set("pd_read_csv", function(path:Dynamic) return readCsv(g(), path));
	}

	public static function build(?grantsOf:Void->Null<musescript.io.IoGrant>):Dynamic {
		var g = grantsOf == null ? function() return null : grantsOf;
		var pd:Dynamic = {};
		for (k in METHOD_NAMES.keys())
			Reflect.setField(pd, k, METHOD_NAMES.get(k));
		Reflect.setField(pd, "read_csv", function(path:Dynamic) return readCsv(g(), path));
		return pd;
	}

	public static final FLAT_NAMES:Map<String, Dynamic> = [
		"pd_series" => series, "pd_dataframe" => dataframe, "pd_from_columns" => fromColumns,
		"pd_from_ndarray" => fromNdArray, "pd_empty" => empty,
		"pd_shape" => shapeOf, "pd_columns" => columnsOf, "pd_nrows" => nrowsOf, "pd_ncols" => ncolsOf,
		"pd_index" => indexOf, "pd_get" => getCol, "pd_select" => select, "pd_assign" => assign,
		"pd_drop" => drop, "pd_copy" => copyOf, "pd_head" => headOf, "pd_tail" => tailOf,
		"pd_iloc" => iloc, "pd_to_ndarray" => toNdArray,
		"pd_series_values" => seriesValues, "pd_series_name" => seriesName,
		"pd_series_length" => seriesLength, "pd_index_kind" => indexKind,
		"pd_index_range" => indexRange, "pd_index_floats" => indexFloats, "pd_index_strings" => indexStrings,
		"pd_from_bars" => fromBars, "pd_from_bar_column" => fromBarColumn,
		"pd_from_panel" => fromPanel,
		"pd_reindex" => reindex, "pd_align" => alignFrames, "pd_join" => join,
		"pd_merge_asof" => mergeAsof, "pd_fillna" => fillna, "pd_dropna" => dropna, "pd_isna" => isna,
		"pd_concat" => concat, "pd_concat_cols" => concatCols, "pd_parse_csv" => parseCsv,
		"pd_groupby_agg" => groupbyAgg, "pd_groupby_transform" => groupbyTransform,
		"pd_groupby_rank" => groupbyRank, "pd_groupby_mean" => groupbyMean,
		"pd_groupby_sum" => groupbySum, "pd_groupby_std" => groupbyStd,
		"pd_rank" => rankOf, "pd_xs_rank" => xsRank,
		"pd_shift" => shiftOf, "pd_diff" => diffOf, "pd_pct_change" => pctChangeOf,
		"pd_rolling_mean" => rollingMeanOf, "pd_rolling_sum" => rollingSumOf,
		"pd_rolling_std" => rollingStdOf, "pd_ewm_mean" => ewmMeanOf,
		"pd_groupby_keys_agg" => groupbyKeysAgg,
		"pd_pivot" => pivotOf, "pd_melt" => meltOf, "pd_corr" => corrOf, "pd_cov" => covOf
	];

	static final METHOD_NAMES:Map<String, Dynamic> = [
		"series" => series, "dataframe" => dataframe, "from_columns" => fromColumns,
		"from_ndarray" => fromNdArray, "empty" => empty,
		"shape" => shapeOf, "columns" => columnsOf, "nrows" => nrowsOf, "ncols" => ncolsOf,
		"index" => indexOf, "get" => getCol, "select" => select, "assign" => assign,
		"drop" => drop, "copy" => copyOf, "head" => headOf, "tail" => tailOf,
		"iloc" => iloc, "to_ndarray" => toNdArray,
		"series_values" => seriesValues, "series_name" => seriesName,
		"series_length" => seriesLength, "index_kind" => indexKind,
		"index_range" => indexRange, "index_floats" => indexFloats, "index_strings" => indexStrings,
		"from_bars" => fromBars, "from_bar_column" => fromBarColumn,
		"from_panel" => fromPanel,
		"reindex" => reindex, "align" => alignFrames, "join" => join,
		"merge_asof" => mergeAsof, "fillna" => fillna, "dropna" => dropna, "isna" => isna,
		"concat" => concat, "concat_cols" => concatCols, "parse_csv" => parseCsv,
		"groupby_agg" => groupbyAgg, "groupby_transform" => groupbyTransform,
		"groupby_rank" => groupbyRank, "groupby_mean" => groupbyMean,
		"groupby_sum" => groupbySum, "groupby_std" => groupbyStd,
		"rank" => rankOf, "xs_rank" => xsRank,
		"shift" => shiftOf, "diff" => diffOf, "pct_change" => pctChangeOf,
		"rolling_mean" => rollingMeanOf, "rolling_sum" => rollingSumOf,
		"rolling_std" => rollingStdOf, "ewm_mean" => ewmMeanOf,
		"groupby_keys_agg" => groupbyKeysAgg,
		"pivot" => pivotOf, "melt" => meltOf, "corr" => corrOf, "cov" => covOf
	];

	public static function series(data:Dynamic, ?index:Dynamic, ?name:Dynamic):Series {
		var vals = coerce1d(data);
		var idx = coerceIndex(index, vals.size);
		var nm:Null<String> = name == null ? null : Std.string(name);
		return Series.create(vals, idx, nm);
	}

	public static function dataframe(data:Dynamic, ?index:Dynamic, ?columns:Dynamic):DataFrame {
		return fromColumns(data, index, columns);
	}

	public static function fromColumns(data:Dynamic, ?index:Dynamic, ?columns:Dynamic):DataFrame {
		if (Std.isOfType(data, DataFrame)) return cast data;
		var order = coerceStringList(columns);
		var map = coerceColumnMap(data, order);
		var nrows = 0;
		for (k in map.keys()) {
			var c = map.get(k);
			if (c != null && c.size > nrows) nrows = c.size;
		}
		var idx = coerceIndex(index, nrows);
		return DataFrame.fromColumns(map, idx, order.length > 0 ? order : null);
	}

	public static function fromNdArray(matrix:Dynamic, ?index:Dynamic, ?columns:Dynamic):DataFrame {
		var m = coerceNd(matrix);
		if (m == null) return DataFrame.empty();
		var rows = m.ndim >= 1 ? m.shape[0] : 0;
		if (m.ndim == 1) rows = m.size;
		return DataFrame.fromNdArray(m, coerceIndex(index, rows), coerceStringList(columns));
	}

	public static function empty(?nrows:Dynamic, ?columns:Dynamic):DataFrame {
		var n = nrows == null ? 0 : Std.int(toFloat(nrows));
		return Pd.empty(n, coerceStringList(columns));
	}

	public static function shapeOf(df:Dynamic):Array<Float> {
		var f = asDf(df);
		if (f == null) return [0.0, 0.0];
		var s = f.shape();
		return [s[0] * 1.0, s[1] * 1.0];
	}

	public static function columnsOf(df:Dynamic):Array<String> {
		var f = asDf(df);
		return f == null ? [] : f.columns();
	}

	public static function nrowsOf(df:Dynamic):Float {
		var f = asDf(df);
		return f == null ? 0 : f.nrows();
	}

	public static function ncolsOf(df:Dynamic):Float {
		var f = asDf(df);
		return f == null ? 0 : f.ncols();
	}

	public static function indexOf(df:Dynamic):AnyIndex {
		var f = asDf(df);
		if (f != null) return f.index;
		var s = asSeries(df);
		return s != null ? s.index : Index.range(0);
	}

	public static function getCol(df:Dynamic, name:Dynamic):Series {
		var f = asDf(df);
		if (f == null) return Series.empty(name == null ? null : Std.string(name));
		return f.get(Std.string(name));
	}

	public static function select(df:Dynamic, names:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return f.select(coerceStringList(names));
	}

	public static function assign(df:Dynamic, name:Dynamic, values:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return f.assign(Std.string(name), coerce1d(values));
	}

	public static function drop(df:Dynamic, names:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return f.drop(coerceStringList(names));
	}

	public static function copyOf(obj:Dynamic):Dynamic {
		var f = asDf(obj);
		if (f != null) return f.copy();
		var s = asSeries(obj);
		if (s != null) return s.copy();
		return obj;
	}

	public static function headOf(obj:Dynamic, ?n:Dynamic):Dynamic {
		var nn = n == null ? 5 : Std.int(toFloat(n));
		var f = asDf(obj);
		if (f != null) return f.head(nn);
		var s = asSeries(obj);
		return s != null ? s.head(nn) : null;
	}

	public static function tailOf(obj:Dynamic, ?n:Dynamic):Dynamic {
		var nn = n == null ? 5 : Std.int(toFloat(n));
		var f = asDf(obj);
		if (f != null) return f.tail(nn);
		var s = asSeries(obj);
		return s != null ? s.tail(nn) : null;
	}

	public static function iloc(df:Dynamic, indices:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return f.iloc(coerceIntList(indices));
	}

	public static function toNdArray(df:Dynamic):NdArrayF64 {
		var f = asDf(df);
		return f == null ? NdArrayF64.empty([0, 0]) : f.toNdArray();
	}

	public static function seriesValues(s:Dynamic):NdArrayF64 {
		var ser = asSeries(s);
		return ser == null ? NdArrayF64.empty([0]) : ser.values;
	}

	public static function seriesName(s:Dynamic):String {
		var ser = asSeries(s);
		return ser == null || ser.name == null ? "" : ser.name;
	}

	public static function seriesLength(s:Dynamic):Float {
		var ser = asSeries(s);
		return ser == null ? 0 : ser.length;
	}

	public static function indexKind(idx:Dynamic):String {
		var i = asIndex(idx);
		return i == null ? "" : Index.kindOf(i);
	}

	public static function indexRange(n:Dynamic):AnyIndex
		return Index.range(Std.int(toFloat(n)));

	public static function indexFloats(labels:Dynamic):AnyIndex
		return Index.fromFloats(coerceFloatList(labels));

	public static function indexStrings(labels:Dynamic):AnyIndex
		return Index.fromStrings(coerceStringList(labels));

	public static function fromBars(bars:Dynamic):DataFrame {
		if (Std.isOfType(bars, Array)) return PdBridge.fromBars(cast bars);
		return DataFrame.empty();
	}

	public static function fromBarColumn(bars:Dynamic, key:Dynamic, ?name:Dynamic):Series {
		if (!Std.isOfType(bars, Array)) return Series.empty();
		var nm:Null<String> = name == null ? null : Std.string(name);
		return PdBridge.fromBarDataColumn(cast bars, Std.string(key), nm);
	}

	public static function fromPanel(panel:Dynamic, ?fields:Dynamic):DataFrame {
		if (panel == null) return DataFrame.empty();
		if (Std.isOfType(panel, PanelFeed))
			return PdBridge.fromPanelFeed(cast panel, coerceStringList(fields));
		return DataFrame.empty();
	}

	public static function reindex(df:Dynamic, index:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return Align.reindex(f, coerceIndex(index, f.nrows()));
	}

	public static function alignFrames(left:Dynamic, right:Dynamic, ?how:Dynamic):Dynamic {
		var a = Align.align(asDf(left), asDf(right), how == null ? "outer" : Std.string(how));
		return {left: a.left, right: a.right};
	}

	public static function join(left:Dynamic, right:Dynamic, on:Dynamic, ?how:Dynamic, ?validate:Dynamic):DataFrame {
		return Join.onColumn(
			asDf(left), asDf(right), Std.string(on),
			how == null ? "left" : Std.string(how),
			validate == true
		);
	}

	public static function mergeAsof(
		left:Dynamic,
		right:Dynamic,
		on:Dynamic,
		?by:Dynamic,
		?direction:Dynamic,
		?allowLookahead:Dynamic,
		?tolerance:Dynamic
	):DataFrame {
		var byS:Null<String> = by == null ? null : Std.string(by);
		var dir = direction == null ? "backward" : Std.string(direction);
		var allow = allowLookahead == true;
		var tol:Null<Float> = tolerance == null ? null : toFloat(tolerance);
		return MergeAsof.merge(asDf(left), asDf(right), Std.string(on), byS, dir, allow, tol);
	}

	public static function fillna(df:Dynamic, value:Dynamic):DataFrame
		return FrameNa.fillna(asDf(df), toFloat(value));

	public static function dropna(df:Dynamic, ?how:Dynamic):DataFrame
		return FrameNa.dropna(asDf(df), how == null ? "any" : Std.string(how));

	public static function isna(df:Dynamic):DataFrame
		return FrameNa.isna(asDf(df));

	public static function concat(frames:Dynamic):DataFrame {
		var arr:Array<DataFrame> = [];
		if (Std.isOfType(frames, Array)) {
			for (x in (cast frames : Array<Dynamic>)) {
				var f = asDf(x);
				if (f != null) arr.push(f);
			}
		}
		return Concat.axis0(arr);
	}

	public static function concatCols(left:Dynamic, right:Dynamic, ?rsuffix:Dynamic):DataFrame
		return Concat.axis1(asDf(left), asDf(right), rsuffix == null ? "_r" : Std.string(rsuffix));

	public static function parseCsv(text:Dynamic):DataFrame
		return PdCsv.parse(text == null ? "" : Std.string(text));

	public static function readCsv(?grants:Null<musescript.io.IoGrant>, path:Dynamic):DataFrame
		return PdCsv.readCsv(grants, path == null ? "" : Std.string(path));

	// --- M2: groupby / rank / windows ---

	public static function groupbyAgg(df:Dynamic, by:Dynamic, ?fn:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return GroupBy.create(f, Std.string(by)).agg(fn == null ? "mean" : Std.string(fn));
	}

	public static function groupbyTransform(df:Dynamic, by:Dynamic, ?fn:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return GroupBy.create(f, Std.string(by)).transform(fn == null ? "mean" : Std.string(fn));
	}

	public static function groupbyRank(df:Dynamic, by:Dynamic, ?pct:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return GroupBy.create(f, Std.string(by)).rank(pct == true);
	}

	public static function groupbyMean(df:Dynamic, by:Dynamic):DataFrame
		return groupbyAgg(df, by, "mean");

	public static function groupbySum(df:Dynamic, by:Dynamic):DataFrame
		return groupbyAgg(df, by, "sum");

	public static function groupbyStd(df:Dynamic, by:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return GroupBy.create(f, Std.string(by)).std(1);
	}

	public static function rankOf(obj:Dynamic, ?pct:Dynamic, ?ascending:Dynamic):Dynamic {
		var p = pct == true;
		var asc = ascending == null ? true : ascending != false;
		var s = asSeries(obj);
		if (s != null) return s.rank(p, asc);
		var f = asDf(obj);
		if (f != null) {
			// Ungrouped column-wise rank.
			var order = f.columns();
			var map = new Map<String, NdArrayF64>();
			for (n in order) {
				var col = f.valuesOf(n);
				map.set(n, GroupBy.rank1d(col != null ? col : NdArrayF64.empty([f.nrows()]), p, asc));
			}
			return DataFrame.fromColumns(map, Index.copyOf(f.index), order);
		}
		return null;
	}

	public static function xsRank(df:Dynamic, ?pct:Dynamic, ?ascending:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		var asc = ascending == null ? true : ascending != false;
		return GroupBy.xsRankFrame(f, pct == true, asc);
	}

	public static function shiftOf(obj:Dynamic, ?periods:Dynamic):Dynamic {
		var p = periods == null ? 1 : Std.int(toFloat(periods));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.shiftSeries(s, p);
		var f = asDf(obj);
		return f != null ? FrameWindow.shiftFrame(f, p) : null;
	}

	public static function diffOf(obj:Dynamic, ?periods:Dynamic):Dynamic {
		var p = periods == null ? 1 : Std.int(toFloat(periods));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.diffSeries(s, p);
		var f = asDf(obj);
		return f != null ? FrameWindow.diffFrame(f, p) : null;
	}

	public static function pctChangeOf(obj:Dynamic, ?periods:Dynamic):Dynamic {
		var p = periods == null ? 1 : Std.int(toFloat(periods));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.pctChangeSeries(s, p);
		var f = asDf(obj);
		return f != null ? FrameWindow.pctChangeFrame(f, p) : null;
	}

	public static function rollingMeanOf(obj:Dynamic, window:Dynamic):Dynamic {
		var w = Std.int(toFloat(window));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.rollingMeanSeries(s, w);
		var f = asDf(obj);
		return f != null ? FrameWindow.rollingMeanFrame(f, w) : null;
	}

	public static function rollingSumOf(obj:Dynamic, window:Dynamic):Dynamic {
		var w = Std.int(toFloat(window));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.rollingSumSeries(s, w);
		var f = asDf(obj);
		return f != null ? FrameWindow.rollingSumFrame(f, w) : null;
	}

	public static function rollingStdOf(obj:Dynamic, window:Dynamic, ?ddof:Dynamic):Dynamic {
		var w = Std.int(toFloat(window));
		var d = ddof == null ? 1 : Std.int(toFloat(ddof));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.rollingStdSeries(s, w, d);
		var f = asDf(obj);
		return f != null ? FrameWindow.rollingStdFrame(f, w, d) : null;
	}

	public static function ewmMeanOf(obj:Dynamic, span:Dynamic):Dynamic {
		var sp = Std.int(toFloat(span));
		var s = asSeries(obj);
		if (s != null) return FrameWindow.ewmMeanSeries(s, sp);
		var f = asDf(obj);
		return f != null ? FrameWindow.ewmMeanFrame(f, sp) : null;
	}

	// --- M3: multi-key / reshape / corr ---

	public static function groupbyKeysAgg(df:Dynamic, by:Dynamic, ?fn:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return GroupBy.createKeys(f, coerceStringList(by)).agg(fn == null ? "mean" : Std.string(fn));
	}

	public static function pivotOf(df:Dynamic, index:Dynamic, columns:Dynamic, values:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		return FrameReshape.pivot(f, Std.string(index), Std.string(columns), Std.string(values));
	}

	public static function meltOf(
		df:Dynamic,
		?idVars:Dynamic,
		?valueVars:Dynamic,
		?varName:Dynamic,
		?valueName:Dynamic
	):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		var vn:Null<String> = varName == null ? null : Std.string(varName);
		var valn:Null<String> = valueName == null ? null : Std.string(valueName);
		return FrameReshape.melt(f, coerceStringList(idVars), coerceStringList(valueVars), vn, valn);
	}

	public static function corrOf(df:Dynamic):DataFrame {
		var f = asDf(df);
		return f == null ? DataFrame.empty() : FrameCorr.corr(f);
	}

	public static function covOf(df:Dynamic, ?ddof:Dynamic):DataFrame {
		var f = asDf(df);
		if (f == null) return DataFrame.empty();
		var d = ddof == null ? 1 : Std.int(toFloat(ddof));
		return FrameCorr.cov(f, d);
	}

	// --- coercion ---

	static function asDf(v:Dynamic):Null<DataFrame>
		return Std.isOfType(v, DataFrame) ? cast v : null;

	static function asSeries(v:Dynamic):Null<Series>
		return Std.isOfType(v, Series) ? cast v : null;

	static function asIndex(v:Dynamic):Null<AnyIndex> {
		if (v == null) return null;
		// Enum instances are objects; probe via Index helpers when already AnyIndex-shaped.
		try {
			var _ = Index.kindOf(cast v);
			return cast v;
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function coerceNd(v:Dynamic):Null<NdArrayF64> {
		if (v == null) return null;
		if (Std.isOfType(v, NdArrayF64)) return cast v;
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			if (arr.length > 0 && Std.isOfType(arr[0], Array)) {
				var rows:Array<Array<Float>> = [];
				for (r in arr) {
					if (!Std.isOfType(r, Array)) return null;
					rows.push([for (c in (cast r : Array<Dynamic>)) toFloat(c)]);
				}
				return Np.asarray2d(rows);
			}
			return Np.asarray([for (x in arr) toFloat(x)]);
		}
		return null;
	}

	static function coerce1d(v:Dynamic):NdArrayF64 {
		var s = asSeries(v);
		if (s != null) return s.values;
		var a = coerceNd(v);
		if (a == null) return NdArrayF64.empty([0]);
		if (a.ndim <= 1) return a;
		var c = a.copy();
		var r = c.reshape([c.size]);
		return r != null ? r : NdArrayF64.empty([0]);
	}

	static function coerceIndex(v:Dynamic, fallbackLen:Int):AnyIndex {
		if (v == null) return Index.range(fallbackLen);
		var existing = asIndex(v);
		if (existing != null) return existing;
		if (Std.isOfType(v, IndexF64)) return AnyIndex.F64(cast v);
		if (Std.isOfType(v, NdArrayF64)) return Index.fromNdArray(cast v);
		if (Std.isOfType(v, Array)) {
			var arr:Array<Dynamic> = cast v;
			if (arr.length > 0 && Std.isOfType(arr[0], String))
				return Index.fromStrings([for (x in arr) Std.string(x)]);
			return Index.fromFloats([for (x in arr) toFloat(x)]);
		}
		return Index.range(fallbackLen);
	}

	static function coerceColumnMap(data:Dynamic, order:Array<String>):Map<String, NdArrayF64> {
		var map = new Map<String, NdArrayF64>();
		if (data == null) return map;
		if (Std.isOfType(data, NdArrayF64) || (Std.isOfType(data, Array) && !isObjectMap(data))) {
			var m = coerceNd(data);
			if (m != null) {
				var df = DataFrame.fromNdArray(m, null, order.length > 0 ? order : null);
				for (n in df.columns()) {
					var col = df.valuesOf(n);
					if (col != null) map.set(n, col);
				}
			}
			return map;
		}
		// Object / Map-like: { close: [...], open: [...] }
		if (Std.isOfType(data, haxe.ds.StringMap)) {
			var sm:Map<String, Dynamic> = cast data;
			for (k in sm.keys()) map.set(k, coerce1d(sm.get(k)));
			return map;
		}
		for (f in Reflect.fields(data)) {
			map.set(f, coerce1d(Reflect.field(data, f)));
			if (order.indexOf(f) < 0) order.push(f);
		}
		return map;
	}

	static function isObjectMap(data:Dynamic):Bool {
		if (data == null || Std.isOfType(data, Array) || Std.isOfType(data, NdArrayF64)) return false;
		if (Std.isOfType(data, haxe.ds.StringMap)) return true;
		return Reflect.isObject(data);
	}

	static function coerceStringList(v:Dynamic):Array<String> {
		if (v == null) return [];
		if (Std.isOfType(v, Array)) return [for (x in (cast v : Array<Dynamic>)) Std.string(x)];
		if (Std.isOfType(v, String)) return [Std.string(v)];
		return [];
	}

	static function coerceFloatList(v:Dynamic):Array<Float> {
		if (v == null) return [];
		if (Std.isOfType(v, NdArrayF64)) return (cast v : NdArrayF64).toArray();
		if (Std.isOfType(v, Array)) return [for (x in (cast v : Array<Dynamic>)) toFloat(x)];
		return [];
	}

	static function coerceIntList(v:Dynamic):Array<Int> {
		if (v == null) return [];
		if (Std.isOfType(v, NdArrayF64)) {
			var a:NdArrayF64 = cast v;
			return [for (i in 0...a.size) Std.int(a.getFlat(i))];
		}
		if (Std.isOfType(v, Array)) return [for (x in (cast v : Array<Dynamic>)) Std.int(toFloat(x))];
		return [];
	}

	static function toFloat(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return cast v;
		return Std.parseFloat(Std.string(v));
	}
}
