package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * NaN / empty-string fill / drop helpers (M1).
 * Float NaN + Str `""` as missing (no pandas nullable string / Dynamic NA).
 * fillna fills F64 NaNs only (Str labels preserved as-is).
 * isna returns an **F64 0/1** mask for every column (F64 NaN and Str `""`).
 */
class FrameNa {
	public static function fillna(df:DataFrame, value:Float):DataFrame {
		if (df == null) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		var order = df.f64Columns();
		for (n in order) {
			var src = df.valuesOf(n);
			var col = NdArrayF64.empty([df.nrows()]);
			for (i in 0...df.nrows()) {
				var v = src != null ? src.getFlat(i) : Math.NaN;
				col.setFlat(i, Math.isNaN(v) ? value : v);
			}
			map.set(n, col);
		}
		var sMap = new Map<String, Array<String>>();
		var sOrder = df.strColumns();
		for (n in sOrder) {
			var src = df.strValuesOf(n);
			sMap.set(n, src != null ? src : [for (_ in 0...df.nrows()) ""]);
		}
		return DataFrame.fromColumns(map, Index.copyOf(df.index), order, sMap, sOrder);
	}

	/**
	 * Drop rows where any tracked cell is missing (`how="any"`) or all are
	 * missing (`how="all"`). Missing = F64 NaN or Str `""`.
	 */
	public static function dropna(df:DataFrame, ?how:String = "any"):DataFrame {
		if (df == null) return DataFrame.empty();
		var mode = how == null ? "any" : how.toLowerCase();
		var keep:Array<Int> = [];
		var fNames = df.f64Columns();
		var sNames = df.strColumns();
		var nTrack = fNames.length + sNames.length;
		for (r in 0...df.nrows()) {
			var miss = 0;
			for (n in fNames) {
				var src = df.valuesOf(n);
				var v = src != null ? src.getFlat(r) : Math.NaN;
				if (Math.isNaN(v)) miss++;
			}
			for (n in sNames) {
				var src = df.strValuesOf(n);
				var s = src != null && r < src.length && src[r] != null ? src[r] : "";
				if (s.length == 0) miss++;
			}
			var drop = if (nTrack == 0) false;
			else if (mode == "all") miss == nTrack;
			else miss > 0;
			if (!drop) keep.push(r);
		}
		return df.iloc(keep);
	}

	/** 0/1 F64 mask for every column: F64 NaN and Str `""` → 1. */
	public static function isna(df:DataFrame):DataFrame {
		if (df == null) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		var order:Array<String> = [];
		var n = df.nrows();
		for (name in df.f64Columns()) {
			var src = df.valuesOf(name);
			var col = NdArrayF64.empty([n]);
			for (i in 0...n) {
				var v = src != null ? src.getFlat(i) : Math.NaN;
				col.setFlat(i, Math.isNaN(v) ? 1.0 : 0.0);
			}
			order.push(name);
			map.set(name, col);
		}
		for (name in df.strColumns()) {
			var src = df.strValuesOf(name);
			var col = NdArrayF64.empty([n]);
			for (i in 0...n) {
				var s = src != null && i < src.length && src[i] != null ? src[i] : "";
				col.setFlat(i, s.length == 0 ? 1.0 : 0.0);
			}
			order.push(name);
			map.set(name, col);
		}
		return DataFrame.fromColumns(map, Index.copyOf(df.index), order);
	}
}
