package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Row / column concat (M1).
 * F64 and string sidecar columns are unioned; missing F64 → NaN, missing Str → "".
 */
class Concat {
	/** Stack frames vertically (axis 0). Columns = union; missing → NaN / "". */
	public static function axis0(frames:Array<DataFrame>):DataFrame {
		if (frames == null || frames.length == 0) return DataFrame.empty();
		var fOrder:Array<String> = [];
		var sOrder:Array<String> = [];
		var fSeen = new Map<String, Bool>();
		var sSeen = new Map<String, Bool>();
		var total = 0;
		for (f in frames) {
			if (f == null) continue;
			total += f.nrows();
			for (n in f.f64Columns()) {
				if (!fSeen.exists(n) && !sSeen.exists(n)) {
					fSeen.set(n, true);
					fOrder.push(n);
				}
			}
			for (n in f.strColumns()) {
				if (!sSeen.exists(n)) {
					sSeen.set(n, true);
					sOrder.push(n);
					// Prefer Str when mixed across frames.
					if (fSeen.exists(n)) {
						fSeen.remove(n);
						fOrder = [for (x in fOrder) if (x != n) x];
					}
				}
			}
		}
		if (total == 0) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		for (n in fOrder) map.set(n, NdArrayF64.empty([total]));
		var sMap = new Map<String, Array<String>>();
		for (n in sOrder) sMap.set(n, [for (_ in 0...total) ""]);
		var row = 0;
		var idxLabels:Array<Float> = [];
		var useF64 = true;
		for (f in frames) {
			if (f == null) continue;
			var nf = f.nrows();
			var idx = Index.asF64(f.index);
			if (idx == null) useF64 = false;
			for (i in 0...nf) {
				if (idx != null) idxLabels.push(idx.get(i));
				else idxLabels.push(row + i);
				for (n in fOrder) {
					var src = f.valuesOf(n);
					map.get(n).setFlat(row + i, src != null ? src.getFlat(i) : Math.NaN);
				}
				for (n in sOrder) {
					var labels = f.strValuesOf(n);
					sMap.get(n)[row + i] = (labels != null && i < labels.length) ? labels[i] : "";
				}
			}
			row += nf;
		}
		var index = useF64 ? Index.fromFloats(idxLabels) : Index.range(total);
		return DataFrame.fromColumns(map, index, fOrder, sMap, sOrder);
	}

	/** Side-by-side (axis 1). Requires equal nrows; overlapping names get `_r` suffix. */
	public static function axis1(left:DataFrame, right:DataFrame, ?rsuffix:String = "_r"):DataFrame {
		if (left == null) return right != null ? right.copy() : DataFrame.empty();
		if (right == null) return left.copy();
		if (left.nrows() != right.nrows())
			throw "pd.concat axis=1: nrows must match";
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var sMap = new Map<String, Array<String>>();
		var sOrder:Array<String> = [];
		for (n in left.f64Columns()) {
			order.push(n);
			var v = left.valuesOf(n);
			map.set(n, v != null ? v.copy() : NdArrayF64.empty([left.nrows()]));
		}
		for (n in left.strColumns()) {
			sOrder.push(n);
			var v = left.strValuesOf(n);
			sMap.set(n, v != null ? v : [for (_ in 0...left.nrows()) ""]);
		}
		var suf = rsuffix == null ? "_r" : rsuffix;
		for (n in right.f64Columns()) {
			var out = left.hasColumn(n) ? n + suf : n;
			order.push(out);
			var v = right.valuesOf(n);
			map.set(out, v != null ? v.copy() : NdArrayF64.empty([right.nrows()]));
		}
		for (n in right.strColumns()) {
			var out = left.hasColumn(n) ? n + suf : n;
			sOrder.push(out);
			var v = right.strValuesOf(n);
			sMap.set(out, v != null ? v : [for (_ in 0...right.nrows()) ""]);
		}
		return DataFrame.fromColumns(map, Index.copyOf(left.index), order, sMap, sOrder);
	}
}
