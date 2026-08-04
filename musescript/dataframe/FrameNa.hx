package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * NaN fill / drop helpers (M1). Float NaN only — no pandas NA.
 */
class FrameNa {
	public static function fillna(df:DataFrame, value:Float):DataFrame {
		if (df == null) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		var order = df.columns();
		for (n in order) {
			var src = df.valuesOf(n);
			var col = NdArrayF64.empty([df.nrows()]);
			for (i in 0...df.nrows()) {
				var v = src != null ? src.getFlat(i) : Math.NaN;
				col.setFlat(i, Math.isNaN(v) ? value : v);
			}
			map.set(n, col);
		}
		return DataFrame.fromColumns(map, Index.copyOf(df.index), order);
	}

	/** Drop rows where any column is NaN (`how="any"`) or all are NaN (`how="all"`). */
	public static function dropna(df:DataFrame, ?how:String = "any"):DataFrame {
		if (df == null) return DataFrame.empty();
		var mode = how == null ? "any" : how.toLowerCase();
		var keep:Array<Int> = [];
		var names = df.columns();
		for (r in 0...df.nrows()) {
			var nanCount = 0;
			for (n in names) {
				var src = df.valuesOf(n);
				var v = src != null ? src.getFlat(r) : Math.NaN;
				if (Math.isNaN(v)) nanCount++;
			}
			var drop = mode == "all" ? nanCount == names.length : nanCount > 0;
			if (!drop) keep.push(r);
		}
		return df.iloc(keep);
	}

	public static function isna(df:DataFrame):DataFrame {
		if (df == null) return DataFrame.empty();
		var map = new Map<String, NdArrayF64>();
		var order = df.columns();
		for (n in order) {
			var src = df.valuesOf(n);
			var col = NdArrayF64.empty([df.nrows()]);
			for (i in 0...df.nrows()) {
				var v = src != null ? src.getFlat(i) : Math.NaN;
				col.setFlat(i, Math.isNaN(v) ? 1.0 : 0.0);
			}
			map.set(n, col);
		}
		return DataFrame.fromColumns(map, Index.copyOf(df.index), order);
	}
}
