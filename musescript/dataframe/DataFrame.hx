package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Columnar DataFrame — shared Index + ordered F64 NdArray columns.
 * Optional string sidecar columns (MultiIndex Str reset / string groupby keys /
 * CSV non-numeric / assignStr). No row-object / Dynamic cell API.
 */
class DataFrame {
	var _index:AnyIndex;
	var _names:Array<String>;
	var _cols:Array<NdArrayF64>;
	var _strNames:Array<String>;
	var _strCols:Array<Array<String>>;

	function new(
		index:AnyIndex,
		names:Array<String>,
		cols:Array<NdArrayF64>,
		?strNames:Array<String>,
		?strCols:Array<Array<String>>
	) {
		_index = index;
		_names = names != null ? names : [];
		_cols = cols != null ? cols : [];
		_strNames = strNames != null ? strNames : [];
		_strCols = strCols != null ? strCols : [];
	}

	public static function empty():DataFrame
		return new DataFrame(Index.range(0), [], [], [], []);

	/**
	 * Build from ordered column name → 1-D NdArray map (names follow `columnOrder`
	 * when provided, else sorted keys).
	 */
	public static function fromColumns(
		columns:Map<String, NdArrayF64>,
		?index:AnyIndex,
		?columnOrder:Array<String>,
		?strColumns:Map<String, Array<String>>,
		?strOrder:Array<String>
	):DataFrame {
		if (columns == null) columns = new Map();
		if (strColumns == null && columns.keys().hasNext() == false) return empty();
		// Allow str-only frames (MultiIndex Str reset with no F64 value cols).
		if (!columns.keys().hasNext() && (strColumns == null || !strColumns.keys().hasNext()))
			return empty();
		var names:Array<String> = [];
		if (columnOrder != null && columnOrder.length > 0) {
			for (n in columnOrder) if (columns.exists(n)) names.push(n);
		} else {
			for (k in columns.keys()) names.push(k);
			names.sort(Reflect.compare);
		}
		var cols:Array<NdArrayF64> = [];
		var nrows = 0;
		for (i in 0...names.length) {
			var c = normalize1d(columns.get(names[i]));
			cols.push(c);
			if (c.size > nrows) nrows = c.size;
		}
		var sNames:Array<String> = [];
		var sCols:Array<Array<String>> = [];
		if (strColumns != null) {
			if (strOrder != null && strOrder.length > 0) {
				for (n in strOrder) if (strColumns.exists(n)) sNames.push(n);
			} else {
				for (k in strColumns.keys()) sNames.push(k);
				sNames.sort(Reflect.compare);
			}
			for (n in sNames) {
				var src = strColumns.get(n);
				var labels:Array<String> = src != null ? src.copy() : [];
				if (labels.length > nrows) nrows = labels.length;
				sCols.push(labels);
			}
		}
		// Align shorter F64 columns with NaN.
		for (i in 0...cols.length) {
			if (cols[i].size == nrows) continue;
			var aligned = NdArrayF64.empty([nrows]);
			var n = cols[i].size < nrows ? cols[i].size : nrows;
			for (j in 0...n) aligned.setFlat(j, cols[i].getFlat(j));
			for (j in n...nrows) aligned.setFlat(j, Math.NaN);
			cols[i] = aligned;
		}
		for (i in 0...sCols.length) {
			while (sCols[i].length < nrows) sCols[i].push("");
			if (sCols[i].length > nrows) sCols[i] = sCols[i].slice(0, nrows);
		}
		var idx = index != null ? index : Index.range(nrows);
		var nIdx = Index.lengthOf(idx);
		if (nIdx != nrows) {
			if (nIdx == 0) idx = Index.range(nrows);
			else {
				var target = nIdx;
				for (i in 0...cols.length) {
					var aligned = NdArrayF64.empty([target]);
					var n = cols[i].size < target ? cols[i].size : target;
					for (j in 0...n) aligned.setFlat(j, cols[i].getFlat(j));
					for (j in n...target) aligned.setFlat(j, Math.NaN);
					cols[i] = aligned;
				}
				for (i in 0...sCols.length) {
					while (sCols[i].length < target) sCols[i].push("");
					if (sCols[i].length > target) sCols[i] = sCols[i].slice(0, target);
				}
			}
		}
		return new DataFrame(idx, names, cols, sNames, sCols);
	}

	/**
	 * Matrix (`n × m`) → frame with column names; Index defaults to range(n).
	 * Contiguous columns are extracted as owned 1-D copies (M0: C-contig owned).
	 */
	public static function fromNdArray(
		matrix:NdArrayF64,
		?index:AnyIndex,
		?columns:Array<String>
	):DataFrame {
		if (matrix == null || matrix.size == 0) return empty();
		var m = matrix.ndim == 1 ? (normalize1d(matrix)) : matrix;
		var rows:Int;
		var ncols:Int;
		if (m.ndim == 1) {
			rows = m.size;
			ncols = 1;
		} else if (m.ndim == 2) {
			rows = m.shape[0];
			ncols = m.shape[1];
		} else {
			return empty();
		}
		var names:Array<String> = [];
		if (columns != null && columns.length >= ncols) {
			for (i in 0...ncols) names.push(columns[i]);
		} else {
			for (i in 0...ncols) names.push("c" + i);
		}
		var cols:Array<NdArrayF64> = [];
		if (m.ndim == 1) {
			cols.push(m.isCContiguous() ? m.copy() : m.copy());
		} else {
			for (c in 0...ncols) {
				var col = NdArrayF64.empty([rows]);
				for (r in 0...rows) col.setFlat(r, m.get2(r, c));
				cols.push(col);
			}
		}
		var idx = index != null ? index : Index.range(rows);
		return new DataFrame(idx, names, cols);
	}

	/** Construct from parallel name list + column arrays. */
	public static function fromColumnLists(
		names:Array<String>,
		cols:Array<NdArrayF64>,
		?index:AnyIndex
	):DataFrame {
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		if (names == null) names = [];
		if (cols == null) cols = [];
		var n = names.length < cols.length ? names.length : cols.length;
		for (i in 0...n) {
			order.push(names[i]);
			map.set(names[i], cols[i]);
		}
		return fromColumns(map, index, order);
	}

	public var index(get, never):AnyIndex;
	inline function get_index():AnyIndex return _index;

	public function columns():Array<String> {
		var out = _names.copy();
		for (n in _strNames) out.push(n);
		return out;
	}

	public function f64Columns():Array<String> return _names.copy();

	public function strColumns():Array<String> return _strNames.copy();

	public function nrows():Int return Index.lengthOf(_index);

	public function ncols():Int return _names.length + _strNames.length;

	/** `[nrows, ncols]` */
	public function shape():Array<Int> return [nrows(), ncols()];

	public function emptyFrame():Bool return nrows() == 0 || ncols() == 0;

	public function hasColumn(name:String):Bool {
		for (n in _names) if (n == name) return true;
		for (n in _strNames) if (n == name) return true;
		return false;
	}

	/** True when `name` is a string sidecar column (not F64). */
	public function hasStrColumn(name:String):Bool {
		for (n in _strNames) if (n == name) return true;
		return false;
	}

	/** Raw string sidecar labels (copy). Null when missing. */
	public function strValuesOf(name:String):Null<Array<String>> {
		for (i in 0..._strNames.length)
			if (_strNames[i] == name) return _strCols[i].copy();
		return null;
	}

	function colIndex(name:String):Int {
		for (i in 0..._names.length) if (_names[i] == name) return i;
		return -1;
	}

	function strColIndex(name:String):Int {
		for (i in 0..._strNames.length) if (_strNames[i] == name) return i;
		return -1;
	}

	/**
	 * Column as Series sharing NdArray buffer + Index.
	 * Missing or Str sidecar → empty Series (length 0). Prefer `tryGet` /
	 * `getStr` / `hasStrColumn` when callers must distinguish Str from absent.
	 */
	public function get(name:String):Series {
		var i = colIndex(name);
		if (i < 0) return Series.empty(name);
		return Series.create(_cols[i], _index, name);
	}

	/**
	 * F64 column as Series, or null when missing **or** Str sidecar.
	 * (Series stays F64-only — no Series-of-strings.)
	 */
	public function tryGet(name:String):Null<Series> {
		var i = colIndex(name);
		if (i < 0) return null;
		return Series.create(_cols[i], _index, name);
	}

	/** Str sidecar labels (copy), or null when missing / F64. Alias of `strValuesOf`. */
	public inline function getStr(name:String):Null<Array<String>>
		return strValuesOf(name);

	/** Raw F64 column NdArray (shared). Str columns → null. */
	public function valuesOf(name:String):Null<NdArrayF64> {
		var i = colIndex(name);
		return i < 0 ? null : _cols[i];
	}

	public function select(names:Array<String>):DataFrame {
		if (names == null || names.length == 0) return empty();
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (n in names) {
			var i = colIndex(n);
			if (i >= 0) {
				order.push(n);
				map.set(n, _cols[i]);
				continue;
			}
			var si = strColIndex(n);
			if (si >= 0) {
				sOrder.push(n);
				sMap.set(n, _strCols[si]);
			}
		}
		return fromColumns(map, _index, order, sMap, sOrder);
	}

	/** New frame with F64 column assigned (owned copy of values). */
	public function assign(name:String, values:NdArrayF64):DataFrame {
		var map = f64ColumnMap();
		var order = _names.copy();
		var v = normalize1d(values).copy();
		if (!map.exists(name)) order.push(name);
		map.set(name, v);
		var sMap = strColumnMap();
		var sOrder = _strNames.copy();
		if (sMap.exists(name)) {
			sMap.remove(name);
			sOrder = [for (n in sOrder) if (n != name) n];
		}
		return fromColumns(map, _index, order, sMap, sOrder);
	}

	/** Assign / upsert a string sidecar column. */
	public function assignStr(name:String, labels:Array<String>):DataFrame {
		var map = f64ColumnMap();
		var order = _names.copy();
		var sMap = strColumnMap();
		var sOrder = _strNames.copy();
		var copied = labels != null ? labels.copy() : [];
		if (!sMap.exists(name)) sOrder.push(name);
		sMap.set(name, copied);
		if (map.exists(name)) {
			map.remove(name);
			order = [for (n in order) if (n != name) n];
		}
		return fromColumns(map, _index, order, sMap, sOrder);
	}

	public function drop(names:Array<String>):DataFrame {
		if (names == null || names.length == 0) return copy();
		var dropSet = new Map<String, Bool>();
		for (n in names) dropSet.set(n, true);
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (i in 0..._names.length) {
			if (dropSet.exists(_names[i])) continue;
			order.push(_names[i]);
			map.set(_names[i], _cols[i]);
		}
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (i in 0..._strNames.length) {
			if (dropSet.exists(_strNames[i])) continue;
			sOrder.push(_strNames[i]);
			sMap.set(_strNames[i], _strCols[i]);
		}
		return fromColumns(map, _index, order, sMap, sOrder);
	}

	public function copy():DataFrame {
		var cols:Array<NdArrayF64> = [for (c in _cols) c.copy()];
		var sCols:Array<Array<String>> = [for (c in _strCols) c.copy()];
		return new DataFrame(Index.copyOf(_index), _names.copy(), cols, _strNames.copy(), sCols);
	}

	public function head(n:Int = 5):DataFrame {
		if (n <= 0) return empty();
		var stop = n > nrows() ? nrows() : n;
		return sliceRows(0, stop);
	}

	public function tail(n:Int = 5):DataFrame {
		if (n <= 0) return empty();
		var start = nrows() - n;
		if (start < 0) start = 0;
		return sliceRows(start, nrows());
	}

	public function sliceRows(start:Int, stop:Int):DataFrame {
		var s = start < 0 ? 0 : start;
		var e = stop > nrows() ? nrows() : (stop < 0 ? 0 : stop);
		if (e <= s) return empty();
		var cols:Array<NdArrayF64> = [];
		for (c in _cols) {
			var v = c.slice1d(s, e, 1);
			cols.push(v != null ? v : NdArrayF64.empty([0]));
		}
		var sCols:Array<Array<String>> = [];
		for (c in _strCols) sCols.push(c.slice(s, e));
		return new DataFrame(Index.sliceOf(_index, s, e), _names.copy(), cols, _strNames.copy(), sCols);
	}

	/** Integer-location row take (M0 iloc). */
	public function iloc(indices:Array<Int>):DataFrame {
		if (indices == null || indices.length == 0) return empty();
		var cols:Array<NdArrayF64> = [];
		var n = nrows();
		for (c in _cols) {
			var out = NdArrayF64.empty([indices.length]);
			for (i in 0...indices.length) {
				var ix = indices[i];
				out.setFlat(i, (ix >= 0 && ix < n) ? c.getFlat(ix) : Math.NaN);
			}
			cols.push(out);
		}
		var sCols:Array<Array<String>> = [];
		for (c in _strCols) {
			var out:Array<String> = [];
			for (i in 0...indices.length) {
				var ix = indices[i];
				out.push((ix >= 0 && ix < n) ? c[ix] : "");
			}
			sCols.push(out);
		}
		return new DataFrame(Index.takeOf(_index, indices), _names.copy(), cols, _strNames.copy(), sCols);
	}

	/** Stack F64 columns into owned `n × m` matrix (row-major). Str cols excluded. */
	public function toNdArray():NdArrayF64 {
		var n = nrows();
		var m = _names.length;
		if (n == 0 || m == 0) return NdArrayF64.empty([0, 0]);
		var out = NdArrayF64.empty([n, m]);
		for (c in 0...m)
			for (r in 0...n)
				out.setAt([r, c], _cols[c].getFlat(r));
		return out;
	}

	public function dtypes():Map<String, String> {
		var m = new Map<String, String>();
		for (n in _names) m.set(n, "f64");
		for (n in _strNames) m.set(n, "str");
		return m;
	}

	function f64ColumnMap():Map<String, NdArrayF64> {
		var map = new Map<String, NdArrayF64>();
		for (i in 0..._names.length) map.set(_names[i], _cols[i]);
		return map;
	}

	function strColumnMap():Map<String, Array<String>> {
		var map = new Map<String, Array<String>>();
		for (i in 0..._strNames.length) map.set(_strNames[i], _strCols[i]);
		return map;
	}

	/** Single-key groupby (F64 column). */
	public function groupby(by:String):GroupBy
		return GroupBy.create(this, by);

	public function shift(?periods:Int = 1):DataFrame
		return FrameWindow.shiftFrame(this, periods);

	public function diff(?periods:Int = 1):DataFrame
		return FrameWindow.diffFrame(this, periods);

	public function pctChange(?periods:Int = 1):DataFrame
		return FrameWindow.pctChangeFrame(this, periods);

	public function rollingMean(window:Int):DataFrame
		return FrameWindow.rollingMeanFrame(this, window);

	public function rollingSum(window:Int):DataFrame
		return FrameWindow.rollingSumFrame(this, window);

	public function rollingStd(window:Int, ?ddof:Int = 1):DataFrame
		return FrameWindow.rollingStdFrame(this, window, ddof);

	public function ewmMean(span:Int):DataFrame
		return FrameWindow.ewmMeanFrame(this, span);

	/** Cross-section rank across columns (wide panel). */
	public function xsRank(?pct:Bool = false, ?ascending:Bool = true):DataFrame
		return GroupBy.xsRankFrame(this, pct, ascending);

	public function groupbyKeys(by:Array<String>):GroupBy
		return GroupBy.createKeys(this, by);

	public function pivot(index:String, columns:String, values:String):DataFrame
		return FrameReshape.pivot(this, index, columns, values);

	public function melt(
		?idVars:Array<String>,
		?valueVars:Array<String>,
		?varName:String,
		?valueName:String
	):DataFrame
		return FrameReshape.melt(this, idVars, valueVars, varName, valueName);

	public function corr():DataFrame
		return FrameCorr.corr(this);

	public function cov(?ddof:Int = 1):DataFrame
		return FrameCorr.cov(this, ddof);

	/** Resample / down-sample — see {@link Resample.agg}. */
	public function resample(rule:String, ?how:String = "ohlcv"):DataFrame
		return Resample.agg(this, rule, how);

	/**
	 * Promote Index labels to columns; replace Index with `range(n)`.
	 * MultiIndex → named level columns (F64 → NdArray; Str → sidecar);
	 * F64 Index → `"index"` (or `name`); Str Index → sidecar column.
	 * `drop=true` discards labels.
	 */
	public function resetIndex(?drop:Bool = false, ?name:String = "index"):DataFrame {
		var n = nrows();
		var map = f64ColumnMap();
		for (k in map.keys()) map.set(k, map.get(k).copy());
		var order = _names.copy();
		var sMap = strColumnMap();
		for (k in sMap.keys()) sMap.set(k, sMap.get(k).copy());
		var sOrder = _strNames.copy();
		if (!drop) {
			switch (_index) {
				case Multi(mi):
					var nm = mi.names();
					var insertAt = 0;
					for (lv in 0...mi.nlevels) {
						var baseName = lv < nm.length ? nm[lv] : ("level_" + lv);
						if (mi.levelKind(lv) == "str") {
							var colName = uniqueStrColName(baseName, map, sMap);
							var labels = mi.levelValuesStr(lv);
							while (labels.length < n) labels.push("");
							if (labels.length > n) labels = labels.slice(0, n);
							sMap.set(colName, labels);
							sOrder.insert(insertAt, colName);
						} else {
							var colName = uniqueColName(baseName, map, sMap);
							var vals = NdArrayF64.empty([n]);
							var arr = mi.levelValues(lv);
							for (r in 0...n) vals.setFlat(r, r < arr.length ? arr[r] : Math.NaN);
							map.set(colName, vals);
							order.insert(insertAt, colName);
						}
						insertAt++;
					}
				case F64(idx):
					var colName = uniqueColName(name != null ? name : "index", map, sMap);
					var vals = NdArrayF64.empty([n]);
					for (r in 0...n) vals.setFlat(r, idx.get(r));
					map.set(colName, vals);
					order.insert(0, colName);
				case Str(idx):
					var colName = uniqueStrColName(name != null ? name : "index", map, sMap);
					var labels = idx.labels();
					while (labels.length < n) labels.push("");
					if (labels.length > n) labels = labels.slice(0, n);
					sMap.set(colName, labels);
					sOrder.insert(0, colName);
			}
		}
		return fromColumns(map, Index.range(n), order, sMap, sOrder);
	}

	/**
	 * Cross-section on MultiIndex: keep rows where F64 `level` equals `key`.
	 * Remaining levels become Index (F64 / Str / Multi). Non-Multi → empty.
	 */
	public function xs(key:Float, ?level:Int = 0):DataFrame {
		var mi = Index.asMulti(_index);
		if (mi == null) return empty();
		var pos = mi.xsPositions(key, level);
		return xsPositions(mi, pos, level);
	}

	/** Cross-section where Str `level` equals `key`. */
	public function xsStr(key:String, ?level:Int = 0):DataFrame {
		var mi = Index.asMulti(_index);
		if (mi == null) return empty();
		var pos = mi.xsPositionsStr(key, level);
		return xsPositions(mi, pos, level);
	}

	function xsPositions(mi:MultiIndex, pos:Array<Int>, level:Int):DataFrame {
		if (pos.length == 0) return empty();
		var taken = iloc(pos);
		var remaining = mi.take(pos).withoutLevel(level);
		var map = taken.f64ColumnMap();
		var order = taken.f64Columns();
		var sMap = taken.strColumnMap();
		var sOrder = taken.strColumns();
		return fromColumns(map, remaining.toAnyIndex(), order, sMap, sOrder);
	}

	/** Level values as F64 array; Str levels → []; non-Multi level 0 → F64 Index labels. */
	public function getLevelValues(level:Int = 0):Array<Float> {
		return switch (_index) {
			case Multi(mi): mi.levelValues(level);
			case F64(i): level == 0 ? i.toArray() : [];
			case Str(_): [];
		};
	}

	/** Level values as strings; F64 levels → stringified; non-Multi Str Index when level=0. */
	public function getLevelValuesStr(level:Int = 0):Array<String> {
		return switch (_index) {
			case Multi(mi):
				if (mi.levelKind(level) == "str") return mi.levelValuesStr(level);
				var f = mi.levelValues(level);
				return [for (v in f) Math.isNaN(v) ? "" : Std.string(v)];
			case Str(i): level == 0 ? i.labels() : [];
			case F64(i):
				if (level != 0) return [];
				[for (v in i.toArray()) Math.isNaN(v) ? "" : Std.string(v)];
		};
	}

	static function uniqueColName(
		base:String,
		map:Map<String, NdArrayF64>,
		?strMap:Map<String, Array<String>>
	):String {
		var b = base != null && base != "" ? base : "index";
		if (!map.exists(b) && (strMap == null || !strMap.exists(b))) return b;
		var i = 0;
		while (map.exists(b + "_" + i) || (strMap != null && strMap.exists(b + "_" + i))) i++;
		return b + "_" + i;
	}

	static function uniqueStrColName(
		base:String,
		map:Map<String, NdArrayF64>,
		strMap:Map<String, Array<String>>
	):String
		return uniqueColName(base, map, strMap);

	static function normalize1d(data:NdArrayF64):NdArrayF64 {
		if (data == null) return NdArrayF64.empty([0]);
		if (data.ndim <= 1) return data;
		var c = data.copy();
		var r = c.reshape([c.size]);
		return r != null ? r : NdArrayF64.empty([0]);
	}
}
