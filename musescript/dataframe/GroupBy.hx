package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Groupby (M2 single-key / M3 multi-key) — agg / transform / rank over F64 keys.
 *
 * NaN keys form their own group. Duplicate labels OK.
 * Rank uses average ties (pandas default); NaN stays NaN (not ranked).
 *
 * Multi-key: composite tag from all `by` columns. Agg uses `as_index=False`
 * shape (key columns restored) + range Index — MultiIndex is M4+.
 * Single-key agg keeps F64 key Index (M2 behavior).
 */
class GroupBy {
	var _df:DataFrame;
	var _byCols:Array<String>;
	/** First key column values in group order (single-key Index); unused for multi. */
	var _keys:Array<Float>;
	/** Per group, one Float per by-col (multi-key agg restore). */
	var _keyRows:Array<Array<Float>>;
	var _members:Array<Array<Int>>;

	function new(
		df:DataFrame,
		byCols:Array<String>,
		keys:Array<Float>,
		keyRows:Array<Array<Float>>,
		members:Array<Array<Int>>
	) {
		_df = df;
		_byCols = byCols != null ? byCols : [];
		_keys = keys != null ? keys : [];
		_keyRows = keyRows != null ? keyRows : [];
		_members = members != null ? members : [];
	}

	public static function create(df:DataFrame, by:String):GroupBy {
		if (by == null || by == "") return empty(df, []);
		return createKeys(df, [by]);
	}

	/** Multi-key groupby over ordered F64 columns. */
	public static function createKeys(df:DataFrame, by:Array<String>):GroupBy {
		if (df == null || by == null || by.length == 0) return empty(df, by);
		var cols:Array<NdArrayF64> = [];
		var names:Array<String> = [];
		for (b in by) {
			if (b == null || b == "") continue;
			var c = df.valuesOf(b);
			if (c == null) continue;
			names.push(b);
			cols.push(c);
		}
		if (names.length == 0) return empty(df, by);
		var n = df.nrows();
		var keyOrder:Array<Float> = [];
		var keyRows:Array<Array<Float>> = [];
		var members:Array<Array<Int>> = [];
		var first = new Map<String, Int>();
		var nk = cols.length;
		for (r in 0...n) {
			var tagParts:Array<String> = [];
			var rowKeys:Array<Float> = [];
			for (c in 0...nk) {
				var k = cols[c].getFlat(r);
				rowKeys.push(k);
				tagParts.push(keyTag(k));
			}
			var tag = tagParts.join("\x1f");
			var gi = first.get(tag);
			if (gi == null) {
				gi = keyRows.length;
				first.set(tag, gi);
				keyOrder.push(rowKeys[0]);
				keyRows.push(rowKeys);
				members.push([]);
			}
			members[gi].push(r);
		}
		return new GroupBy(df, names, keyOrder, keyRows, members);
	}

	static function empty(df:DataFrame, by:Null<Array<String>>):GroupBy
		return new GroupBy(
			df != null ? df : DataFrame.empty(),
			by != null ? by : [],
			[],
			[],
			[]
		);

	public function ngroups():Int return _members.length;

	/** Primary / first by column (compat). */
	public function by():String
		return _byCols.length > 0 ? _byCols[0] : "";

	public function byCols():Array<String> return _byCols.copy();

	/** Aggregate all non-`by` columns with one reducer (`mean` default). */
	public function agg(?fn:String = "mean"):DataFrame {
		var op = normalizeOp(fn);
		var names = valueCols();
		var g = _members.length;
		if (g == 0) return DataFrame.empty();
		var multi = _byCols.length > 1;
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		if (multi) {
			for (bi in 0..._byCols.length) {
				var out = NdArrayF64.empty([g]);
				for (gi in 0...g) out.setFlat(gi, _keyRows[gi][bi]);
				map.set(_byCols[bi], out);
				order.push(_byCols[bi]);
			}
		}
		if (names.length == 0 && !multi) return DataFrame.empty();
		for (name in names) {
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([g]);
			for (gi in 0...g) out.setFlat(gi, reduceGroup(src, _members[gi], op));
			map.set(name, out);
			order.push(name);
		}
		if (order.length == 0) return DataFrame.empty();
		var idx = multi ? Index.range(g) : Index.fromFloats(_keys.copy());
		return DataFrame.fromColumns(map, idx, order);
	}

	public function mean():DataFrame return agg("mean");
	public function sum():DataFrame return agg("sum");
	public function min():DataFrame return agg("min");
	public function max():DataFrame return agg("max");
	public function count():DataFrame return agg("count");
	public function std(?ddof:Int = 1):DataFrame {
		var g = _members.length;
		if (g == 0) return DataFrame.empty();
		var d = ddof < 0 ? 0 : ddof;
		var multi = _byCols.length > 1;
		var names = valueCols();
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		if (multi) {
			for (bi in 0..._byCols.length) {
				var out = NdArrayF64.empty([g]);
				for (gi in 0...g) out.setFlat(gi, _keyRows[gi][bi]);
				map.set(_byCols[bi], out);
				order.push(_byCols[bi]);
			}
		}
		for (name in names) {
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([g]);
			for (gi in 0...g) out.setFlat(gi, stdGroup(src, _members[gi], d));
			map.set(name, out);
			order.push(name);
		}
		if (order.length == 0) return DataFrame.empty();
		var idx = multi ? Index.range(g) : Index.fromFloats(_keys.copy());
		return DataFrame.fromColumns(map, idx, order);
	}

	/**
	 * Broadcast group reduction back to original row shape.
	 * Ops: mean, sum, min, max, count, std, zscore.
	 * `by` columns are copied through unchanged.
	 */
	public function transform(?fn:String = "mean"):DataFrame {
		var op = normalizeOp(fn);
		var n = _df.nrows();
		var order = _df.columns();
		var bySet = bySetMap();
		var map = new Map<String, NdArrayF64>();
		for (name in order) {
			if (bySet.exists(name)) {
				var src = _df.valuesOf(name);
				map.set(name, src != null ? src.copy() : NdArrayF64.empty([n]));
				continue;
			}
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([n]);
			for (i in 0...n) out.setFlat(i, Math.NaN);
			for (gi in 0..._members.length) {
				var rows = _members[gi];
				if (op == "zscore") {
					var mu = reduceGroup(src, rows, "mean");
					var sd = stdGroup(src, rows, 1);
					for (r in rows) {
						var v = src != null ? src.getFlat(r) : Math.NaN;
						if (Math.isNaN(v) || Math.isNaN(sd) || sd == 0)
							out.setFlat(r, Math.NaN);
						else
							out.setFlat(r, (v - mu) / sd);
					}
				} else {
					var red = reduceGroup(src, rows, op);
					for (r in rows) out.setFlat(r, red);
				}
			}
			map.set(name, out);
		}
		return DataFrame.fromColumns(map, Index.copyOf(_df.index), order);
	}

	/**
	 * Within-group ranks for each value column (average ties).
	 * `pct=true` → percentile ranks in (0,1]. NaNs stay NaN.
	 */
	public function rank(?pct:Bool = false, ?ascending:Bool = true):DataFrame {
		var n = _df.nrows();
		var order = _df.columns();
		var bySet = bySetMap();
		var map = new Map<String, NdArrayF64>();
		for (name in order) {
			if (bySet.exists(name)) {
				var src = _df.valuesOf(name);
				map.set(name, src != null ? src.copy() : NdArrayF64.empty([n]));
				continue;
			}
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([n]);
			for (i in 0...n) out.setFlat(i, Math.NaN);
			for (gi in 0..._members.length)
				rankInto(src, _members[gi], out, pct, ascending);
			map.set(name, out);
		}
		return DataFrame.fromColumns(map, Index.copyOf(_df.index), order);
	}

	function bySetMap():Map<String, Bool> {
		var m = new Map<String, Bool>();
		for (b in _byCols) m.set(b, true);
		return m;
	}

	function valueCols():Array<String> {
		var bySet = bySetMap();
		var out:Array<String> = [];
		for (n in _df.columns()) if (!bySet.exists(n)) out.push(n);
		return out;
	}

	static function normalizeOp(fn:Null<String>):String {
		if (fn == null || fn == "") return "mean";
		var s = fn.toLowerCase();
		return switch (s) {
			case "mean" | "avg" | "average": "mean";
			case "sum" | "total": "sum";
			case "min": "min";
			case "max": "max";
			case "count" | "size": "count";
			case "std" | "stdev" | "stddev": "std";
			case "zscore" | "z": "zscore";
			default: "mean";
		};
	}

	/** Stable string tag for map keys (shared by pivot). */
	public static function keyTag(k:Float):String {
		if (Math.isNaN(k)) return "__nan__";
		return Std.string(k);
	}

	static function reduceGroup(src:Null<NdArrayF64>, rows:Array<Int>, op:String):Float {
		if (rows == null || rows.length == 0) return Math.NaN;
		var count = 0;
		var sum = 0.0;
		var minV = Math.POSITIVE_INFINITY;
		var maxV = Math.NEGATIVE_INFINITY;
		for (r in rows) {
			var v = src != null ? src.getFlat(r) : Math.NaN;
			if (Math.isNaN(v)) continue;
			count++;
			sum += v;
			if (v < minV) minV = v;
			if (v > maxV) maxV = v;
		}
		return switch (op) {
			case "count": count * 1.0;
			case "sum": count == 0 ? Math.NaN : sum;
			case "mean": count == 0 ? Math.NaN : sum / count;
			case "min": count == 0 ? Math.NaN : minV;
			case "max": count == 0 ? Math.NaN : maxV;
			case "std": stdGroup(src, rows, 1);
			default: count == 0 ? Math.NaN : sum / count;
		};
	}

	static function stdGroup(src:Null<NdArrayF64>, rows:Array<Int>, ddof:Int):Float {
		if (rows == null || rows.length == 0) return Math.NaN;
		var count = 0;
		var sum = 0.0;
		for (r in rows) {
			var v = src != null ? src.getFlat(r) : Math.NaN;
			if (Math.isNaN(v)) continue;
			count++;
			sum += v;
		}
		if (count <= ddof) return Math.NaN;
		var mean = sum / count;
		var acc = 0.0;
		for (r in rows) {
			var v = src != null ? src.getFlat(r) : Math.NaN;
			if (Math.isNaN(v)) continue;
			var d = v - mean;
			acc += d * d;
		}
		return Math.sqrt(acc / (count - ddof));
	}

	/** Average-tie rank into `out` for the given member rows. */
	public static function rankInto(
		src:Null<NdArrayF64>,
		rows:Array<Int>,
		out:NdArrayF64,
		pct:Bool,
		ascending:Bool
	):Void {
		if (rows == null || rows.length == 0) return;
		var vals:Array<{r:Int, v:Float}> = [];
		for (r in rows) {
			var v = src != null ? src.getFlat(r) : Math.NaN;
			if (!Math.isNaN(v)) vals.push({r: r, v: v});
		}
		var m = vals.length;
		if (m == 0) return;
		vals.sort(function(a, b) {
			if (a.v < b.v) return ascending ? -1 : 1;
			if (a.v > b.v) return ascending ? 1 : -1;
			return a.r < b.r ? -1 : (a.r > b.r ? 1 : 0);
		});
		var i = 0;
		while (i < m) {
			var j = i + 1;
			while (j < m && vals[j].v == vals[i].v) j++;
			// ranks are 1-based positions i+1 .. j (inclusive end j)
			var avgRank = (i + 1 + j) / 2.0;
			var score = pct ? (avgRank / m) : avgRank;
			for (k in i...j) out.setFlat(vals[k].r, score);
			i = j;
		}
	}

	/** Global (ungrouped) rank of a 1-D column. */
	public static function rank1d(src:NdArrayF64, ?pct:Bool = false, ?ascending:Bool = true):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) out.setFlat(i, Math.NaN);
		var rows = [for (i in 0...n) i];
		rankInto(src, rows, out, pct, ascending);
		return out;
	}

	/**
	 * Cross-section rank: each row ranked across columns (wide panel DNA).
	 * Returns same shape; NaN cells stay NaN and are excluded from that row's ranks.
	 */
	public static function xsRankFrame(df:DataFrame, ?pct:Bool = false, ?ascending:Bool = true):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var names = df.columns();
		var n = df.nrows();
		var m = names.length;
		var outs:Array<NdArrayF64> = [for (_ in 0...m) NdArrayF64.empty([n])];
		for (c in 0...m)
			for (r in 0...n)
				outs[c].setFlat(r, Math.NaN);
		for (r in 0...n) {
			var vals:Array<{c:Int, v:Float}> = [];
			for (c in 0...m) {
				var src = df.valuesOf(names[c]);
				var v = src != null ? src.getFlat(r) : Math.NaN;
				if (!Math.isNaN(v)) vals.push({c: c, v: v});
			}
			var k = vals.length;
			if (k == 0) continue;
			vals.sort(function(a, b) {
				if (a.v < b.v) return ascending ? -1 : 1;
				if (a.v > b.v) return ascending ? 1 : -1;
				return a.c < b.c ? -1 : (a.c > b.c ? 1 : 0);
			});
			var i = 0;
			while (i < k) {
				var j = i + 1;
				while (j < k && vals[j].v == vals[i].v) j++;
				var avgRank = (i + 1 + j) / 2.0;
				var score = pct ? (avgRank / k) : avgRank;
				for (t in i...j) outs[vals[t].c].setFlat(r, score);
				i = j;
			}
		}
		var map = new Map<String, NdArrayF64>();
		for (c in 0...m) map.set(names[c], outs[c]);
		return DataFrame.fromColumns(map, Index.copyOf(df.index), names);
	}
}
