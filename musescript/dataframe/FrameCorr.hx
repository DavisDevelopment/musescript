package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Pairwise corr / cov on numeric (F64) columns (M3).
 *
 * Pearson corr; sample cov with `ddof=1` (pandas default). Pairwise complete
 * observations per column pair (skip rows where either cell is NaN).
 * Result is square DataFrame: columns = column names, Index = IndexStr names.
 */
class FrameCorr {
	public static function corr(df:DataFrame):DataFrame
		return pairwise(df, true, 1);

	public static function cov(df:DataFrame, ?ddof:Int = 1):DataFrame
		return pairwise(df, false, ddof < 0 ? 0 : ddof);

	static function pairwise(df:DataFrame, asCorr:Bool, ddof:Int):DataFrame {
		if (df == null || df.emptyFrame()) return DataFrame.empty();
		var names = df.columns();
		var m = names.length;
		if (m == 0) return DataFrame.empty();
		var cols:Array<NdArrayF64> = [];
		for (n in names) {
			var c = df.valuesOf(n);
			cols.push(c != null ? c : NdArrayF64.empty([df.nrows()]));
		}
		var n = df.nrows();
		var outs:Array<NdArrayF64> = [for (_ in 0...m) NdArrayF64.empty([m])];
		for (i in 0...m) {
			for (j in 0...m) {
				var v = asCorr ? pearson(cols[i], cols[j], n) : covariance(cols[i], cols[j], n, ddof);
				outs[j].setFlat(i, v);
			}
		}
		var map = new Map<String, NdArrayF64>();
		for (j in 0...m) map.set(names[j], outs[j]);
		return DataFrame.fromColumns(map, Index.fromStrings(names.copy()), names);
	}

	static function pearson(a:NdArrayF64, b:NdArrayF64, n:Int):Float {
		var count = 0;
		var sumA = 0.0;
		var sumB = 0.0;
		for (r in 0...n) {
			var x = a.getFlat(r);
			var y = b.getFlat(r);
			if (Math.isNaN(x) || Math.isNaN(y)) continue;
			count++;
			sumA += x;
			sumB += y;
		}
		if (count < 2) return Math.NaN;
		var meanA = sumA / count;
		var meanB = sumB / count;
		var num = 0.0;
		var denA = 0.0;
		var denB = 0.0;
		for (r in 0...n) {
			var x = a.getFlat(r);
			var y = b.getFlat(r);
			if (Math.isNaN(x) || Math.isNaN(y)) continue;
			var da = x - meanA;
			var db = y - meanB;
			num += da * db;
			denA += da * da;
			denB += db * db;
		}
		var den = Math.sqrt(denA * denB);
		if (den == 0 || Math.isNaN(den)) return Math.NaN;
		return num / den;
	}

	static function covariance(a:NdArrayF64, b:NdArrayF64, n:Int, ddof:Int):Float {
		var count = 0;
		var sumA = 0.0;
		var sumB = 0.0;
		for (r in 0...n) {
			var x = a.getFlat(r);
			var y = b.getFlat(r);
			if (Math.isNaN(x) || Math.isNaN(y)) continue;
			count++;
			sumA += x;
			sumB += y;
		}
		if (count <= ddof) return Math.NaN;
		var meanA = sumA / count;
		var meanB = sumB / count;
		var acc = 0.0;
		for (r in 0...n) {
			var x = a.getFlat(r);
			var y = b.getFlat(r);
			if (Math.isNaN(x) || Math.isNaN(y)) continue;
			acc += (x - meanA) * (y - meanB);
		}
		return acc / (count - ddof);
	}
}
