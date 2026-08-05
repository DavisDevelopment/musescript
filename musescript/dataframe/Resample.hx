package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Causal resample / down-sample for bar frames (M4 comfort).
 *
 * Rules:
 *   - Bar count: `"5"`, `"5B"`, `"5b"` → groups of N consecutive rows
 *   - Duration (F64 time index, usually ms): `"1s"`, `"1m"`, `"5m"`, `"1h"`, `"1d"`,
 *     or `"3600000ms"` / bare integer ms string ending in `ms`
 *
 * Agg `how`:
 *   - `"ohlcv"` (default) — per-column OHLCV semantics for open/high/low/close/volume
 *     (case-insensitive); other columns use `last`
 *   - `"mean"` / `"sum"` / `"min"` / `"max"` / `"first"` / `"last"` — uniform
 *
 * Bin label = **last** index label in the bucket (bar close time). PIT-safe: only
 * past rows contribute to a bucket; no center / forward fill.
 * String sidecars: **last non-empty** label in the bucket (else `""`).
 */
class Resample {
	public static function agg(df:DataFrame, rule:String, ?how:String = "ohlcv"):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var parsed = parseRule(rule);
		if (parsed == null)
			throw 'Resample: unsupported rule "$rule" (use Nb / Ns / Nm / Nh / Nd / Nms)';
		var buckets = switch (parsed.kind) {
			case Bars: bucketByBars(df.nrows(), parsed.n);
			case DurationMs: bucketByDuration(df, parsed.n);
		};
		if (buckets.length == 0) return DataFrame.empty();
		return reduceBuckets(df, buckets, how == null ? "ohlcv" : how);
	}

	/** Convenience: OHLCV-aware agg. */
	public static inline function ohlcv(df:DataFrame, rule:String):DataFrame
		return agg(df, rule, "ohlcv");

	public static function parseRule(rule:String):Null<{kind:ResampleKind, n:Float}> {
		if (rule == null) return null;
		var s = StringTools.trim(rule).toLowerCase();
		if (s.length == 0) return null;
		var i = 0;
		while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) i++;
		if (i == 0) return null;
		var nDig = Std.parseFloat(s.substr(0, i));
		if (Math.isNaN(nDig) || nDig <= 0) return null;
		var unit = s.substr(i);
		if (unit.length == 0 || unit == "b")
			return {kind: Bars, n: nDig};
		var ms = switch (unit) {
			case "ms": nDig;
			case "s": nDig * 1000.0;
			case "m": nDig * 60.0 * 1000.0;
			case "h": nDig * 3600.0 * 1000.0;
			case "d": nDig * 86400.0 * 1000.0;
			default: Math.NaN;
		};
		if (Math.isNaN(ms) || ms <= 0) return null;
		return {kind: DurationMs, n: ms};
	}

	static function bucketByBars(nrows:Int, nBars:Float):Array<{start:Int, stop:Int}> {
		var w = Std.int(nBars);
		if (w < 1) w = 1;
		var out:Array<{start:Int, stop:Int}> = [];
		var i = 0;
		while (i < nrows) {
			var stop = i + w;
			if (stop > nrows) stop = nrows;
			out.push({start: i, stop: stop});
			i = stop;
		}
		return out;
	}

	/**
	 * Left-closed / right-open bins on index times relative to first label:
	 * `floor((t - t0) / width)`.
	 */
	static function bucketByDuration(df:DataFrame, widthMs:Float):Array<{start:Int, stop:Int}> {
		var idx = Index.asF64(df.index);
		if (idx == null)
			throw "Resample: duration rules require an F64 (time) index";
		var n = df.nrows();
		if (n == 0) return [];
		var t0 = idx.get(0);
		if (Math.isNaN(t0)) t0 = 0.0;
		var out:Array<{start:Int, stop:Int}> = [];
		var start = 0;
		var curBin = binId(idx.get(0), t0, widthMs);
		for (i in 1...n) {
			var b = binId(idx.get(i), t0, widthMs);
			if (b != curBin) {
				out.push({start: start, stop: i});
				start = i;
				curBin = b;
			}
		}
		out.push({start: start, stop: n});
		return out;
	}

	static inline function binId(t:Float, t0:Float, width:Float):Int {
		var x = Math.isNaN(t) ? t0 : t;
		return Std.int(Math.floor((x - t0) / width));
	}

	static function reduceBuckets(
		df:DataFrame,
		buckets:Array<{start:Int, stop:Int}>,
		how:String
	):DataFrame {
		var names = df.f64Columns();
		var nb = buckets.length;
		var map = new Map<String, NdArrayF64>();
		var labelTimes = NdArrayF64.empty([nb]);
		var idxF = Index.asF64(df.index);
		for (bi in 0...nb) {
			var b = buckets[bi];
			var last = b.stop - 1;
			labelTimes.setFlat(bi, idxF != null ? idxF.get(last) : last * 1.0);
		}
		for (name in names) {
			var src = df.valuesOf(name);
			var col = NdArrayF64.empty([nb]);
			var op = resolveOp(name, how);
			for (bi in 0...nb) {
				var b = buckets[bi];
				col.setFlat(bi, reduceRange(src, b.start, b.stop, op));
			}
			map.set(name, col);
		}
		var sMap = new Map<String, Array<String>>();
		var sOrder = df.strColumns();
		for (name in sOrder) {
			var src = df.strValuesOf(name);
			var labels:Array<String> = [];
			for (bi in 0...nb) {
				var b = buckets[bi];
				labels.push(reduceStrRange(src, b.start, b.stop));
			}
			sMap.set(name, labels);
		}
		var outIdx:AnyIndex = idxF != null
			? Index.fromNdArray(labelTimes)
			: Index.range(nb);
		return DataFrame.fromColumns(map, outIdx, names, sMap, sOrder);
	}

	/** Last non-empty label in `[start, stop)`; else `""`. */
	static function reduceStrRange(src:Null<Array<String>>, start:Int, stop:Int):String {
		if (src == null || stop <= start) return "";
		var i = stop - 1;
		while (i >= start) {
			if (i < src.length && src[i] != null && src[i].length > 0) return src[i];
			i--;
		}
		return "";
	}

	static function resolveOp(colName:String, how:String):String {
		var h = how.toLowerCase();
		if (h == "ohlcv") {
			var c = colName.toLowerCase();
			// strip field@SYM → field
			var at = c.indexOf("@");
			if (at > 0) c = c.substr(0, at);
			return switch (c) {
				case "open" | "o": "first";
				case "high" | "h": "max";
				case "low" | "l": "min";
				case "close" | "c" | "adj_close" | "adjclose": "last";
				case "volume" | "vol" | "v": "sum";
				default: "last";
			};
		}
		return switch (h) {
			case "mean" | "sum" | "min" | "max" | "first" | "last": h;
			default: "last";
		};
	}

	static function reduceRange(src:Null<NdArrayF64>, start:Int, stop:Int, op:String):Float {
		if (src == null || stop <= start) return Math.NaN;
		switch (op) {
			case "first":
				for (i in start...stop) {
					var v = src.getFlat(i);
					if (!Math.isNaN(v)) return v;
				}
				return Math.NaN;
			case "last":
				var i = stop - 1;
				while (i >= start) {
					var v = src.getFlat(i);
					if (!Math.isNaN(v)) return v;
					i--;
				}
				return Math.NaN;
			case "min":
				var mn = Math.NaN;
				for (i in start...stop) {
					var v = src.getFlat(i);
					if (Math.isNaN(v)) continue;
					mn = Math.isNaN(mn) ? v : (v < mn ? v : mn);
				}
				return mn;
			case "max":
				var mx = Math.NaN;
				for (i in start...stop) {
					var v = src.getFlat(i);
					if (Math.isNaN(v)) continue;
					mx = Math.isNaN(mx) ? v : (v > mx ? v : mx);
				}
				return mx;
			case "sum":
				var sum = 0.0;
				var any = false;
				for (i in start...stop) {
					var v = src.getFlat(i);
					if (Math.isNaN(v)) continue;
					sum += v;
					any = true;
				}
				return any ? sum : Math.NaN;
			default: // mean
				var s = 0.0;
				var c = 0;
				for (i in start...stop) {
					var v = src.getFlat(i);
					if (Math.isNaN(v)) continue;
					s += v;
					c++;
				}
				return c > 0 ? s / c : Math.NaN;
		}
	}
}

enum ResampleKind {
	Bars;
	DurationMs;
}
