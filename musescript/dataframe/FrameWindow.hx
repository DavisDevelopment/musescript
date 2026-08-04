package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Causal window ops on Series / DataFrame columns (M2).
 *
 * shift / diff / pct_change / rolling / ewm — past-looking only (no `center=`).
 * PIT: rolling/ewm on asof-filled frames still only sees past *filled* values;
 * they do not invent future. Prefer ingest-time asof so feature timing is audited.
 */
class FrameWindow {
	public static function shiftSeries(s:Series, ?periods:Int = 1):Series {
		if (s == null) return Series.empty();
		return Series.create(shift1d(s.values, periods), Index.copyOf(s.index), s.name);
	}

	public static function diffSeries(s:Series, ?periods:Int = 1):Series {
		if (s == null) return Series.empty();
		return Series.create(diff1d(s.values, periods), Index.copyOf(s.index), s.name);
	}

	public static function pctChangeSeries(s:Series, ?periods:Int = 1):Series {
		if (s == null) return Series.empty();
		return Series.create(pctChange1d(s.values, periods), Index.copyOf(s.index), s.name);
	}

	public static function shiftFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return mapCols(df, function(c) return shift1d(c, periods));

	public static function diffFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return mapCols(df, function(c) return diff1d(c, periods));

	public static function pctChangeFrame(df:DataFrame, ?periods:Int = 1):DataFrame
		return mapCols(df, function(c) return pctChange1d(c, periods));

	/** Rolling mean; first `window-1` rows are NaN (pandas min_periods=window). */
	public static function rollingMeanSeries(s:Series, window:Int):Series
		return Series.create(rollingReduce(s.values, window, "mean"), Index.copyOf(s.index), s.name);

	public static function rollingSumSeries(s:Series, window:Int):Series
		return Series.create(rollingReduce(s.values, window, "sum"), Index.copyOf(s.index), s.name);

	public static function rollingMinSeries(s:Series, window:Int):Series
		return Series.create(rollingReduce(s.values, window, "min"), Index.copyOf(s.index), s.name);

	public static function rollingMaxSeries(s:Series, window:Int):Series
		return Series.create(rollingReduce(s.values, window, "max"), Index.copyOf(s.index), s.name);

	public static function rollingStdSeries(s:Series, window:Int, ?ddof:Int = 1):Series
		return Series.create(rollingStd(s.values, window, ddof), Index.copyOf(s.index), s.name);

	public static function rollingMeanFrame(df:DataFrame, window:Int):DataFrame
		return mapCols(df, function(c) return rollingReduce(c, window, "mean"));

	public static function rollingSumFrame(df:DataFrame, window:Int):DataFrame
		return mapCols(df, function(c) return rollingReduce(c, window, "sum"));

	public static function rollingStdFrame(df:DataFrame, window:Int, ?ddof:Int = 1):DataFrame
		return mapCols(df, function(c) return rollingStd(c, window, ddof));

	/**
	 * EWM mean with `span` (pandas adjust=false / recursive form).
	 * alpha = 2 / (span + 1). Leading NaNs skipped until first finite seed.
	 */
	public static function ewmMeanSeries(s:Series, span:Int):Series
		return Series.create(ewmMean1d(s.values, span), Index.copyOf(s.index), s.name);

	public static function ewmMeanFrame(df:DataFrame, span:Int):DataFrame
		return mapCols(df, function(c) return ewmMean1d(c, span));

	static function mapCols(df:DataFrame, f:NdArrayF64->NdArrayF64):DataFrame {
		if (df == null) return DataFrame.empty();
		var order = df.columns();
		var map = new Map<String, NdArrayF64>();
		for (n in order) {
			var src = df.valuesOf(n);
			map.set(n, f(src != null ? src : NdArrayF64.empty([df.nrows()])));
		}
		return DataFrame.fromColumns(map, Index.copyOf(df.index), order);
	}

	public static function shift1d(src:NdArrayF64, periods:Int):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var out = NdArrayF64.empty([n]);
		var p = periods;
		for (i in 0...n) {
			var j = i - p;
			out.setFlat(i, (j >= 0 && j < n && src != null) ? src.getFlat(j) : Math.NaN);
		}
		return out;
	}

	public static function diff1d(src:NdArrayF64, periods:Int):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var p = periods < 1 ? 1 : periods;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) {
			if (i < p || src == null) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var a = src.getFlat(i);
			var b = src.getFlat(i - p);
			out.setFlat(i, (Math.isNaN(a) || Math.isNaN(b)) ? Math.NaN : a - b);
		}
		return out;
	}

	public static function pctChange1d(src:NdArrayF64, periods:Int):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var p = periods < 1 ? 1 : periods;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) {
			if (i < p || src == null) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var a = src.getFlat(i);
			var b = src.getFlat(i - p);
			if (Math.isNaN(a) || Math.isNaN(b) || b == 0)
				out.setFlat(i, Math.NaN);
			else
				out.setFlat(i, (a - b) / b);
		}
		return out;
	}

	public static function rollingReduce(src:NdArrayF64, window:Int, op:String):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var w = window < 1 ? 1 : window;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) {
			if (i + 1 < w) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var start = i - w + 1;
			var count = 0;
			var sum = 0.0;
			var minV = Math.POSITIVE_INFINITY;
			var maxV = Math.NEGATIVE_INFINITY;
			var valid = true;
			for (j in start...(i + 1)) {
				var v = src.getFlat(j);
				if (Math.isNaN(v)) {
					valid = false;
					break;
				}
				count++;
				sum += v;
				if (v < minV) minV = v;
				if (v > maxV) maxV = v;
			}
			if (!valid || count == 0) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			out.setFlat(i, switch (op) {
				case "sum": sum;
				case "min": minV;
				case "max": maxV;
				default: sum / count;
			});
		}
		return out;
	}

	public static function rollingStd(src:NdArrayF64, window:Int, ddof:Int):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var w = window < 1 ? 1 : window;
		var d = ddof < 0 ? 0 : ddof;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) {
			if (i + 1 < w) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var start = i - w + 1;
			var count = 0;
			var sum = 0.0;
			var ok = true;
			for (j in start...(i + 1)) {
				var v = src.getFlat(j);
				if (Math.isNaN(v)) {
					ok = false;
					break;
				}
				count++;
				sum += v;
			}
			if (!ok || count <= d) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var mean = sum / count;
			var acc = 0.0;
			for (j in start...(i + 1)) {
				var v = src.getFlat(j);
				var dv = v - mean;
				acc += dv * dv;
			}
			out.setFlat(i, Math.sqrt(acc / (count - d)));
		}
		return out;
	}

	public static function ewmMean1d(src:NdArrayF64, span:Int):NdArrayF64 {
		var n = src != null ? src.size : 0;
		var sp = span < 1 ? 1 : span;
		var alpha = 2.0 / (sp + 1.0);
		var out = NdArrayF64.empty([n]);
		var started = false;
		var prev = Math.NaN;
		for (i in 0...n) {
			var v = src != null ? src.getFlat(i) : Math.NaN;
			if (Math.isNaN(v)) {
				out.setFlat(i, started ? prev : Math.NaN);
				continue;
			}
			if (!started) {
				prev = v;
				started = true;
				out.setFlat(i, prev);
			} else {
				prev = alpha * v + (1.0 - alpha) * prev;
				out.setFlat(i, prev);
			}
		}
		return out;
	}
}
