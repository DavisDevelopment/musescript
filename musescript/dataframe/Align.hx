package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Reindex / take via position maps (M1).
 * Label align for F64 Index — first match wins on duplicate labels.
 */
class Align {
	/** Positions in `source` for each label in `target` (−1 = missing). */
	public static function mapF64(source:IndexF64, target:IndexF64):Array<Int> {
		var nT = target.length;
		var out:Array<Int> = [for (_ in 0...nT) -1];
		if (source == null || target == null) return out;
		// Build first-occurrence hash for source labels.
		var first = new Map<String, Int>();
		for (i in 0...source.length) {
			var k = keyF64(source.get(i));
			if (!first.exists(k)) first.set(k, i);
		}
		for (j in 0...nT) {
			var k = keyF64(target.get(j));
			if (first.exists(k)) out[j] = first.get(k);
		}
		return out;
	}

	public static function mapStr(source:IndexStr, target:IndexStr):Array<Int> {
		var nT = target.length;
		var out:Array<Int> = [for (_ in 0...nT) -1];
		if (source == null || target == null) return out;
		var first = new Map<String, Int>();
		for (i in 0...source.length) {
			var k = source.get(i);
			if (k == null) k = "";
			if (!first.exists(k)) first.set(k, i);
		}
		for (j in 0...nT) {
			var k = target.get(j);
			if (k == null) k = "";
			if (first.exists(k)) out[j] = first.get(k);
		}
		return out;
	}

	/** Tuple-key map for MultiIndex (first match wins). */
	public static function mapMulti(source:MultiIndex, target:MultiIndex):Array<Int> {
		var nT = target != null ? target.length : 0;
		var out:Array<Int> = [for (_ in 0...nT) -1];
		if (source == null || target == null) return out;
		var first = new Map<String, Int>();
		for (i in 0...source.length) {
			var k = source.rowTag(i);
			if (!first.exists(k)) first.set(k, i);
		}
		for (j in 0...nT) {
			var k = target.rowTag(j);
			if (first.exists(k)) out[j] = first.get(k);
		}
		return out;
	}

	/** Reindex frame rows to `newIndex` (label join); missing → NaN. */
	public static function reindex(df:DataFrame, newIndex:AnyIndex):DataFrame {
		if (df == null) return DataFrame.empty();
		if (newIndex == null) return df.copy();
		var mapper = switch [df.index, newIndex] {
			case [F64(s), F64(t)]: mapF64(s, t);
			case [Str(s), Str(t)]: mapStr(s, t);
			case [Multi(s), Multi(t)]: mapMulti(s, t);
			default: [for (_ in 0...Index.lengthOf(newIndex)) -1];
		};
		return takeRows(df, mapper, newIndex);
	}

	/**
	 * Align two frames on union/intersection of Indices.
	 * `how`: "outer" (default) | "inner" | "left" | "right"
	 */
	public static function align(
		left:DataFrame,
		right:DataFrame,
		?how:String = "outer"
	):{left:DataFrame, right:DataFrame} {
		if (left == null) left = DataFrame.empty();
		if (right == null) right = DataFrame.empty();
		var mode = how == null ? "outer" : how.toLowerCase();
		var idx = switch (mode) {
			case "inner": intersectIndex(left.index, right.index);
			case "left": Index.copyOf(left.index);
			case "right": Index.copyOf(right.index);
			default: unionIndex(left.index, right.index);
		};
		return {
			left: reindex(left, idx),
			right: reindex(right, idx)
		};
	}

	public static function takeRows(df:DataFrame, positions:Array<Int>, ?index:AnyIndex):DataFrame {
		if (df == null) return DataFrame.empty();
		var n = positions != null ? positions.length : 0;
		var idx = index != null ? index : Index.range(n);
		var map = new Map<String, NdArrayF64>();
		var order = df.f64Columns();
		var nrows = df.nrows();
		for (name in order) {
			var src = df.valuesOf(name);
			var col = NdArrayF64.empty([n]);
			for (i in 0...n) {
				var p = positions[i];
				col.setFlat(i, (p >= 0 && p < nrows && src != null) ? src.getFlat(p) : Math.NaN);
			}
			map.set(name, col);
		}
		var sMap = new Map<String, Array<String>>();
		var sOrder = df.strColumns();
		for (name in sOrder) {
			var src = df.strValuesOf(name);
			var labels:Array<String> = [];
			for (i in 0...n) {
				var p = positions[i];
				labels.push((p >= 0 && p < nrows && src != null && p < src.length) ? src[p] : "");
			}
			sMap.set(name, labels);
		}
		return DataFrame.fromColumns(map, idx, order, sMap, sOrder);
	}

	static function keyF64(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		return Std.string(v);
	}

	static function unionIndex(a:AnyIndex, b:AnyIndex):AnyIndex {
		return switch [a, b] {
			case [F64(x), F64(y)]:
				var seen = new Map<String, Bool>();
				var labels:Array<Float> = [];
				for (i in 0...x.length) {
					var v = x.get(i);
					var k = keyF64(v);
					if (!seen.exists(k)) {
						seen.set(k, true);
						labels.push(v);
					}
				}
				for (i in 0...y.length) {
					var v = y.get(i);
					var k = keyF64(v);
					if (!seen.exists(k)) {
						seen.set(k, true);
						labels.push(v);
					}
				}
				Index.fromFloats(labels);
			case [Str(x), Str(y)]:
				var seen = new Map<String, Bool>();
				var labels:Array<String> = [];
				for (i in 0...x.length) {
					var v = x.get(i);
					if (v == null) v = "";
					if (!seen.exists(v)) {
						seen.set(v, true);
						labels.push(v);
					}
				}
				for (i in 0...y.length) {
					var v = y.get(i);
					if (v == null) v = "";
					if (!seen.exists(v)) {
						seen.set(v, true);
						labels.push(v);
					}
				}
				Index.fromStrings(labels);
			default:
				Index.copyOf(a);
		};
	}

	static function intersectIndex(a:AnyIndex, b:AnyIndex):AnyIndex {
		return switch [a, b] {
			case [F64(x), F64(y)]:
				var inB = new Map<String, Bool>();
				for (i in 0...y.length) inB.set(keyF64(y.get(i)), true);
				var labels:Array<Float> = [];
				var seen = new Map<String, Bool>();
				for (i in 0...x.length) {
					var v = x.get(i);
					var k = keyF64(v);
					if (inB.exists(k) && !seen.exists(k)) {
						seen.set(k, true);
						labels.push(v);
					}
				}
				Index.fromFloats(labels);
			case [Str(x), Str(y)]:
				var inB = new Map<String, Bool>();
				for (i in 0...y.length) {
					var v = y.get(i);
					inB.set(v == null ? "" : v, true);
				}
				var labels:Array<String> = [];
				var seen = new Map<String, Bool>();
				for (i in 0...x.length) {
					var v = x.get(i);
					if (v == null) v = "";
					if (inB.exists(v) && !seen.exists(v)) {
						seen.set(v, true);
						labels.push(v);
					}
				}
				Index.fromStrings(labels);
			default:
				Index.range(0);
		};
	}
}
