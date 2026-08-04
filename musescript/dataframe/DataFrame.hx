package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Columnar DataFrame — shared Index + ordered F64 NdArray columns.
 * No row-object / Dynamic cell API. Column select returns Series sharing buffer.
 */
class DataFrame {
	var _index:AnyIndex;
	var _names:Array<String>;
	var _cols:Array<NdArrayF64>;

	function new(index:AnyIndex, names:Array<String>, cols:Array<NdArrayF64>) {
		_index = index;
		_names = names != null ? names : [];
		_cols = cols != null ? cols : [];
	}

	public static function empty():DataFrame
		return new DataFrame(Index.range(0), [], []);

	/**
	 * Build from ordered column name → 1-D NdArray map (names follow `columnOrder`
	 * when provided, else sorted keys).
	 */
	public static function fromColumns(
		columns:Map<String, NdArrayF64>,
		?index:AnyIndex,
		?columnOrder:Array<String>
	):DataFrame {
		if (columns == null) return empty();
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
		// Align shorter columns with NaN.
		for (i in 0...cols.length) {
			if (cols[i].size == nrows) continue;
			var aligned = NdArrayF64.empty([nrows]);
			var n = cols[i].size < nrows ? cols[i].size : nrows;
			for (j in 0...n) aligned.setFlat(j, cols[i].getFlat(j));
			for (j in n...nrows) aligned.setFlat(j, Math.NaN);
			cols[i] = aligned;
		}
		var idx = index != null ? index : Index.range(nrows);
		var nIdx = Index.lengthOf(idx);
		if (nIdx != nrows) {
			if (nIdx == 0) idx = Index.range(nrows);
			else {
				// Re-align columns to index length.
				var target = nIdx;
				for (i in 0...cols.length) {
					var aligned = NdArrayF64.empty([target]);
					var n = cols[i].size < target ? cols[i].size : target;
					for (j in 0...n) aligned.setFlat(j, cols[i].getFlat(j));
					for (j in n...target) aligned.setFlat(j, Math.NaN);
					cols[i] = aligned;
				}
			}
		}
		return new DataFrame(idx, names, cols);
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

	public function columns():Array<String> return _names.copy();

	public function nrows():Int return Index.lengthOf(_index);

	public function ncols():Int return _names.length;

	/** `[nrows, ncols]` */
	public function shape():Array<Int> return [nrows(), ncols()];

	public function emptyFrame():Bool return nrows() == 0 || ncols() == 0;

	public function hasColumn(name:String):Bool {
		for (n in _names) if (n == name) return true;
		return false;
	}

	function colIndex(name:String):Int {
		for (i in 0..._names.length) if (_names[i] == name) return i;
		return -1;
	}

	/** Column as Series sharing NdArray buffer + Index. Missing → empty Series. */
	public function get(name:String):Series {
		var i = colIndex(name);
		if (i < 0) return Series.empty(name);
		return Series.create(_cols[i], _index, name);
	}

	/** Raw column NdArray (shared). */
	public function valuesOf(name:String):Null<NdArrayF64> {
		var i = colIndex(name);
		return i < 0 ? null : _cols[i];
	}

	public function select(names:Array<String>):DataFrame {
		if (names == null || names.length == 0) return empty();
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (n in names) {
			var i = colIndex(n);
			if (i < 0) continue;
			order.push(n);
			map.set(n, _cols[i]);
		}
		return fromColumns(map, _index, order);
	}

	/** New frame with column assigned (owned copy of values). */
	public function assign(name:String, values:NdArrayF64):DataFrame {
		var map = new Map<String, NdArrayF64>();
		var order = _names.copy();
		for (i in 0..._names.length) map.set(_names[i], _cols[i]);
		var v = normalize1d(values).copy();
		if (!map.exists(name)) order.push(name);
		map.set(name, v);
		return fromColumns(map, _index, order);
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
		return fromColumns(map, _index, order);
	}

	public function copy():DataFrame {
		var cols:Array<NdArrayF64> = [for (c in _cols) c.copy()];
		return new DataFrame(Index.copyOf(_index), _names.copy(), cols);
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
		return new DataFrame(Index.sliceOf(_index, s, e), _names.copy(), cols);
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
		return new DataFrame(Index.takeOf(_index, indices), _names.copy(), cols);
	}

	/** Stack columns into owned `n × m` matrix (row-major). */
	public function toNdArray():NdArrayF64 {
		var n = nrows();
		var m = ncols();
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
		return m;
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

	static function normalize1d(data:NdArrayF64):NdArrayF64 {
		if (data == null) return NdArrayF64.empty([0]);
		if (data.ndim <= 1) return data;
		var c = data.copy();
		var r = c.reshape([c.size]);
		return r != null ? r : NdArrayF64.empty([0]);
	}
}
