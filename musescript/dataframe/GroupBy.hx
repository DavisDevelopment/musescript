package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Groupby (M2 single-key / M3 multi-key) — agg / transform / rank over F64 and Str keys.
 *
 * NaN / empty-string keys form their own group. Duplicate labels OK.
 * Rank uses average ties (pandas default); NaN stays NaN (not ranked).
 *
 * Multi-key agg default `as_index=false` (M3): key columns restored + range Index.
 * `as_index=true` → MultiIndex on the row Index (all by-cols as levels, F64 and/or Str).
 */
class GroupBy {
	var _df:DataFrame;
	var _byCols:Array<String>;
	var _byKinds:Array<String>; // "f64" | "str" per by-col
	/** First key column values in group order (single-key F64 Index); unused for multi / Str. */
	var _keys:Array<Float>;
	/** Per group, one KeyCell per by-col. */
	var _keyRows:Array<Array<KeyCell>>;
	var _members:Array<Array<Int>>;

	function new(
		df:DataFrame,
		byCols:Array<String>,
		byKinds:Array<String>,
		keys:Array<Float>,
		keyRows:Array<Array<KeyCell>>,
		members:Array<Array<Int>>
	) {
		_df = df;
		_byCols = byCols != null ? byCols : [];
		_byKinds = byKinds != null ? byKinds : [];
		_keys = keys != null ? keys : [];
		_keyRows = keyRows != null ? keyRows : [];
		_members = members != null ? members : [];
	}

	public static function create(df:DataFrame, by:String):GroupBy {
		if (by == null || by == "") return empty(df, []);
		return createKeys(df, [by]);
	}

	/**
	 * Multi-key groupby over ordered F64 and/or Str columns.
	 * Partitions via Factorize codes (dropNa=false so NaN stays groupable) —
	 * int code tags avoid building string keys per row.
	 */
	public static function createKeys(df:DataFrame, by:Array<String>):GroupBy {
		if (df == null || by == null || by.length == 0) return empty(df, by);
		var names:Array<String> = [];
		var kinds:Array<String> = [];
		for (b in by) {
			if (b == null || b == "") continue;
			if (df.hasStrColumn(b)) {
				names.push(b);
				kinds.push("str");
			} else if (df.valuesOf(b) != null) {
				names.push(b);
				kinds.push("f64");
			}
		}
		if (names.length == 0) return empty(df, by);
		var n = df.nrows();
		var nk = names.length;
		// dropNa=false: NaN / empty-string remain groupable uniques (compat).
		var colCodes:Array<Array<Int>> = [];
		var colUniques:Array<FactorUniques> = [];
		for (c in 0...nk) {
			var fr:FactorizeResult;
			if (kinds[c] == "str") {
				var raw = df.strValuesOf(names[c]);
				var labels:Array<String> = [];
				for (r in 0...n) labels.push(raw != null && r < raw.length && raw[r] != null ? raw[r] : "");
				fr = Factorize.str(labels, false);
			} else {
				var col = df.valuesOf(names[c]);
				var vals:Array<Float> = [];
				for (r in 0...n) vals.push(col != null ? col.getFlat(r) : Math.NaN);
				fr = Factorize.f64(vals, false);
			}
			colCodes.push(fr.codes);
			colUniques.push(fr.uniques);
		}
		var keyOrder:Array<Float> = [];
		var keyRows:Array<Array<KeyCell>> = [];
		var members:Array<Array<Int>> = [];
		var first = new Map<String, Int>();
		for (r in 0...n) {
			var tagParts:Array<String> = [];
			for (c in 0...nk) tagParts.push(Std.string(colCodes[c][r]));
			var tag = tagParts.join("\x1f");
			var gi = first.get(tag);
			if (gi == null) {
				gi = keyRows.length;
				first.set(tag, gi);
				var rowKeys:Array<KeyCell> = [];
				for (c in 0...nk) {
					var code = colCodes[c][r];
					rowKeys.push(switch (colUniques[c]) {
						case F64(u): KeyCell.F64(code >= 0 && code < u.length ? u.get(code) : Math.NaN);
						case Str(u):
							var s = code >= 0 && code < u.length ? u.get(code) : "";
							KeyCell.Str(s != null ? s : "");
					});
				}
				switch (rowKeys[0]) {
					case F64(v): keyOrder.push(v);
					case Str(_): keyOrder.push(Math.NaN);
				}
				keyRows.push(rowKeys);
				members.push([]);
			}
			members[gi].push(r);
		}
		return new GroupBy(df, names, kinds, keyOrder, keyRows, members);
	}

	static function empty(df:DataFrame, by:Null<Array<String>>):GroupBy
		return new GroupBy(
			df != null ? df : DataFrame.empty(),
			by != null ? by : [],
			[],
			[],
			[],
			[]
		);

	public function ngroups():Int return _members.length;

	/** Primary / first by column (compat). */
	public function by():String
		return _byCols.length > 0 ? _byCols[0] : "";

	public function byCols():Array<String> return _byCols.copy();

	/**
	 * Aggregate all non-`by` F64 columns with one reducer (`mean` default).
	 * `asIndex`: null = auto (single-key true / multi-key false for M3 compat).
	 * Multi + true → MultiIndex (all by-cols as levels).
	 */
	public function agg(?fn:String = "mean", ?asIndex:Null<Bool> = null):DataFrame {
		var op = normalizeOp(fn);
		var names = valueCols();
		var g = _members.length;
		if (g == 0) return DataFrame.empty();
		var multi = _byCols.length > 1;
		var useAsIndex = asIndex != null ? asIndex : !multi;
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		if (!useAsIndex) {
			emitKeyColumns(g, map, order, sMap, sOrder);
		}
		if (names.length == 0 && order.length == 0 && sOrder.length == 0) return DataFrame.empty();
		for (name in names) {
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([g]);
			for (gi in 0...g) out.setFlat(gi, reduceGroup(src, _members[gi], op));
			map.set(name, out);
			order.push(name);
		}
		if (order.length == 0 && sOrder.length == 0) return DataFrame.empty();
		var idx = buildAggIndex(g, useAsIndex, multi);
		return DataFrame.fromColumns(map, idx, order, sMap, sOrder);
	}

	public function mean(?asIndex:Null<Bool> = null):DataFrame return agg("mean", asIndex);
	public function sum(?asIndex:Null<Bool> = null):DataFrame return agg("sum", asIndex);
	public function min(?asIndex:Null<Bool> = null):DataFrame return agg("min", asIndex);
	public function max(?asIndex:Null<Bool> = null):DataFrame return agg("max", asIndex);
	public function count(?asIndex:Null<Bool> = null):DataFrame return agg("count", asIndex);
	public function std(?ddof:Int = 1, ?asIndex:Null<Bool> = null):DataFrame {
		var g = _members.length;
		if (g == 0) return DataFrame.empty();
		var d = ddof < 0 ? 0 : ddof;
		var multi = _byCols.length > 1;
		var useAsIndex = asIndex != null ? asIndex : !multi;
		var names = valueCols();
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		if (!useAsIndex) {
			emitKeyColumns(g, map, order, sMap, sOrder);
		}
		for (name in names) {
			var src = _df.valuesOf(name);
			var out = NdArrayF64.empty([g]);
			for (gi in 0...g) out.setFlat(gi, stdGroup(src, _members[gi], d));
			map.set(name, out);
			order.push(name);
		}
		if (order.length == 0 && sOrder.length == 0) return DataFrame.empty();
		var idx = buildAggIndex(g, useAsIndex, multi);
		return DataFrame.fromColumns(map, idx, order, sMap, sOrder);
	}

	function emitKeyColumns(
		g:Int,
		map:Map<String, NdArrayF64>,
		order:Array<String>,
		sMap:Map<String, Array<String>>,
		sOrder:Array<String>
	):Void {
		for (bi in 0..._byCols.length) {
			if (_byKinds[bi] == "str") {
				var labels:Array<String> = [];
				for (gi in 0...g) {
					switch (_keyRows[gi][bi]) {
						case Str(s): labels.push(s != null ? s : "");
						case F64(v): labels.push(Math.isNaN(v) ? "" : Std.string(v));
					}
				}
				sMap.set(_byCols[bi], labels);
				sOrder.push(_byCols[bi]);
			} else {
				var out = NdArrayF64.empty([g]);
				for (gi in 0...g) {
					switch (_keyRows[gi][bi]) {
						case F64(v): out.setFlat(gi, v);
						case Str(_): out.setFlat(gi, Math.NaN);
					}
				}
				map.set(_byCols[bi], out);
				order.push(_byCols[bi]);
			}
		}
	}

	function buildAggIndex(g:Int, useAsIndex:Bool, multi:Bool):AnyIndex {
		if (!useAsIndex) return Index.range(g);
		if (multi) {
			return Index.fromMulti(MultiIndex.fromKeyCells(_keyRows, _byCols.copy()));
		}
		// Single key
		if (hasStrBy()) {
			var labels:Array<String> = [];
			for (gi in 0...g) {
				switch (_keyRows[gi][0]) {
					case Str(s): labels.push(s != null ? s : "");
					case F64(v): labels.push(Math.isNaN(v) ? "" : Std.string(v));
				}
			}
			return Index.fromStrings(labels);
		}
		return Index.fromFloats(_keys.copy());
	}

	function hasStrBy():Bool {
		for (k in _byKinds) if (k == "str") return true;
		return false;
	}

	/**
	 * Broadcast group reduction back to original row shape.
	 * Ops: mean, sum, min, max, count, std, zscore.
	 * `by` columns are copied through unchanged.
	 */
	public function transform(?fn:String = "mean"):DataFrame {
		var op = normalizeOp(fn);
		var n = _df.nrows();
		var order = _df.f64Columns();
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
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (n in _df.strColumns()) {
			var src = _df.strValuesOf(n);
			sMap.set(n, src != null ? src : []);
			sOrder.push(n);
		}
		return DataFrame.fromColumns(map, Index.copyOf(_df.index), order, sMap, sOrder);
	}

	/**
	 * Within-group ranks for each value column (average ties).
	 * `pct=true` → percentile ranks in (0,1]. NaNs stay NaN.
	 */
	public function rank(?pct:Bool = false, ?ascending:Bool = true):DataFrame {
		var n = _df.nrows();
		var order = _df.f64Columns();
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
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (nm in _df.strColumns()) {
			var src = _df.strValuesOf(nm);
			sMap.set(nm, src != null ? src : []);
			sOrder.push(nm);
		}
		return DataFrame.fromColumns(map, Index.copyOf(_df.index), order, sMap, sOrder);
	}

	function bySetMap():Map<String, Bool> {
		var m = new Map<String, Bool>();
		for (b in _byCols) m.set(b, true);
		return m;
	}

	function valueCols():Array<String> {
		var bySet = bySetMap();
		var out:Array<String> = [];
		for (n in _df.f64Columns()) if (!bySet.exists(n)) out.push(n);
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
		var names = df.f64Columns();
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
