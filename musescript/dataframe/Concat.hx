package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Row / column concat (M1).
 */
class Concat {
	/** Stack frames vertically (axis 0). Columns = union; missing → NaN. */
	public static function axis0(frames:Array<DataFrame>):DataFrame {
		if (frames == null || frames.length == 0) return DataFrame.empty();
		var order:Array<String> = [];
		var seen = new Map<String, Bool>();
		var total = 0;
		for (f in frames) {
			if (f == null) continue;
			total += f.nrows();
			for (n in f.columns()) {
				if (!seen.exists(n)) {
					seen.set(n, true);
					order.push(n);
				}
			}
		}
		if (total == 0) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		for (n in order) map.set(n, NdArrayF64.empty([total]));
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
				for (n in order) {
					var src = f.valuesOf(n);
					map.get(n).setFlat(row + i, src != null ? src.getFlat(i) : Math.NaN);
				}
			}
			row += nf;
		}
		var index = useF64 ? Index.fromFloats(idxLabels) : Index.range(total);
		return DataFrame.fromColumns(map, index, order);
	}

	/** Side-by-side (axis 1). Requires equal nrows; overlapping names get `_r` suffix. */
	public static function axis1(left:DataFrame, right:DataFrame, ?rsuffix:String = "_r"):DataFrame {
		if (left == null) return right != null ? right.copy() : DataFrame.empty();
		if (right == null) return left.copy();
		if (left.nrows() != right.nrows())
			throw "pd.concat axis=1: nrows must match";
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		for (n in left.columns()) {
			order.push(n);
			var v = left.valuesOf(n);
			map.set(n, v != null ? v.copy() : NdArrayF64.empty([left.nrows()]));
		}
		var suf = rsuffix == null ? "_r" : rsuffix;
		for (n in right.columns()) {
			var out = left.hasColumn(n) ? n + suf : n;
			order.push(out);
			var v = right.valuesOf(n);
			map.set(out, v != null ? v.copy() : NdArrayF64.empty([right.nrows()]));
		}
		return DataFrame.fromColumns(map, Index.copyOf(left.index), order);
	}
}
