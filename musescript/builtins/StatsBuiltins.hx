package musescript.builtins;

// Stale-TODO audit 2026-07-18: skewness/kurtosis/autocorr shipped long ago
// (below); NaN/[]-propagation IS the documented error contract for stats
// (throwing on short samples would break streaming callers mid-backtest).
// The macro-generated numeric/vector-type specialization idea is scoped in
// ROADMAP.md ("Macro-specialized numeric kernels") — not worth doing until a
// profile shows Array<Float> boxing on a real hot path.

/**
 * Dependency-free descriptive statistics over finite numeric vectors.
 *
 * Scalar operations return NaN when their sample is too short or paired
 * vectors have different lengths. Vector operations return [] for [].
 * NaN/infinite inputs follow normal IEEE-754 propagation.
 */
class StatsBuiltins {
	/** Arithmetic mean, accumulated with Neumaier compensation. */
	public static function mean(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		return compensatedSum(xs) / xs.length;
	}

	/** Middle order statistic; even-sized samples average the two middle values. */
	public static function median(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		var sorted = sortedCopy(xs);
		var mid = Std.int(sorted.length / 2);
		return sorted.length % 2 == 1
			? sorted[mid]
			: sorted[mid - 1] + (sorted[mid] - sorted[mid - 1]) / 2.0;
	}

	/** Population variance (divisor n), computed with Welford's algorithm. */
	public static function variance(xs:Array<Float>):Float {
		return varianceWithDivisor(xs, false);
	}

	/** Unbiased sample variance (divisor n - 1); NaN for fewer than two values. */
	public static function sampleVariance(xs:Array<Float>):Float {
		return varianceWithDivisor(xs, true);
	}

	/** Population standard deviation. */
	public static function standardDeviation(xs:Array<Float>):Float {
		var v = variance(xs);
		return Math.sqrt(v);
	}

	/** Sample standard deviation (divisor n - 1). */
	public static function sampleStandardDeviation(xs:Array<Float>):Float {
		var v = sampleVariance(xs);
		return Math.sqrt(v);
	}

	/**
	 * R-7 linear quantile: h = (n - 1) * p, interpolated between floor(h)
	 * and ceil(h). `p` must be in [0, 1].
	 */
	public static function quantile(xs:Array<Float>, p:Float):Float {
		if (xs.length == 0 || Math.isNaN(p) || p < 0.0 || p > 1.0) return Math.NaN;
		var sorted = sortedCopy(xs);
		var h = (sorted.length - 1) * p;
		var lo = Std.int(Math.floor(h));
		var hi = Std.int(Math.ceil(h));
		if (lo == hi) return sorted[lo];
		var weight = h - lo;
		return sorted[lo] + weight * (sorted[hi] - sorted[lo]);
	}

	/**
	 * Sample covariance (divisor n - 1), using an online co-moment update.
	 * Returns NaN for unequal lengths or fewer than two pairs.
	 */
	public static function covariance(xs:Array<Float>, ys:Array<Float>):Float {
		if (xs.length != ys.length || xs.length < 2) return Math.NaN;
		var meanX = 0.0;
		var meanY = 0.0;
		var coMoment = 0.0;
		for (i in 0...xs.length) {
			var n = i + 1.0;
			var dx = xs[i] - meanX;
			meanX += dx / n;
			var dy = ys[i] - meanY;
			meanY += dy / n;
			coMoment += dx * (ys[i] - meanY);
		}
		return coMoment / (xs.length - 1);
	}

	/**
	 * Pearson product-moment correlation. Returns NaN for unequal/short
	 * vectors or when either vector has zero variance.
	 */
	public static function pearson(xs:Array<Float>, ys:Array<Float>):Float {
		if (xs.length != ys.length || xs.length < 2) return Math.NaN;
		var meanX = 0.0;
		var meanY = 0.0;
		var coMoment = 0.0;
		var m2x = 0.0;
		var m2y = 0.0;
		for (i in 0...xs.length) {
			var n = i + 1.0;
			var dx = xs[i] - meanX;
			meanX += dx / n;
			var dy = ys[i] - meanY;
			meanY += dy / n;
			coMoment += dx * (ys[i] - meanY);
			m2x += dx * (xs[i] - meanX);
			m2y += dy * (ys[i] - meanY);
		}
		var den = Math.sqrt(m2x * m2y);
		return den == 0.0 ? Math.NaN : coMoment / den;
	}

	/**
	 * Bias-corrected Fisher-Pearson sample skewness. Returns NaN for fewer
	 * than three values or a constant sample.
	 */
	public static function skewness(xs:Array<Float>):Float {
		var n = xs.length;
		if (n < 3) return Math.NaN;
		var avg = mean(xs);
		var sum2 = 0.0;
		var sum3 = 0.0;
		for (x in xs) {
			var d = x - avg;
			sum2 += d * d;
			sum3 += d * d * d;
		}
		if (sum2 == 0.0) return Math.NaN;
		var sampleStd = Math.sqrt(sum2 / (n - 1));
		return n * sum3 / ((n - 1.0) * (n - 2.0) * sampleStd * sampleStd * sampleStd);
	}

	/**
	 * Bias-corrected excess kurtosis (Fisher). Returns NaN for fewer than
	 * four values or a constant sample.
	 */
	public static function kurtosis(xs:Array<Float>):Float {
		var n = xs.length;
		if (n < 4) return Math.NaN;
		var avg = mean(xs);
		var sum2 = 0.0;
		var sum4 = 0.0;
		for (x in xs) {
			var d = x - avg;
			var d2 = d * d;
			sum2 += d2;
			sum4 += d2 * d2;
		}
		if (sum2 == 0.0) return Math.NaN;
		var m2 = sum2 / n;
		var m4 = sum4 / n;
		var g2 = m4 / (m2 * m2) - 3.0;
		return ((n - 1.0) / ((n - 2.0) * (n - 3.0))) * ((n + 1.0) * g2 + 6.0);
	}

	/**
	 * 1-based average rank of `v` within `xs` (ties share the mean rank).
	 * If `v` is absent, returns insertion rank `1 + count(x < v)`.
	 */
	public static function rank(xs:Array<Float>, v:Float):Float {
		if (xs.length == 0 || Math.isNaN(v)) return Math.NaN;
		var less = 0;
		var equal = 0;
		for (x in xs) {
			if (x < v) less++;
			else if (x == v) equal++;
		}
		if (equal == 0) return less + 1.0;
		return less + (equal + 1.0) / 2.0;
	}

	/**
	 * Percentile rank in [0, 100]: `100 * count(x < v) / n`.
	 * Ties on `v` do not increase the score (scipy `kind='strict'`).
	 */
	public static function percentileRank(xs:Array<Float>, v:Float):Float {
		if (xs.length == 0 || Math.isNaN(v)) return Math.NaN;
		var less = 0;
		for (x in xs) if (x < v) less++;
		return 100.0 * less / xs.length;
	}

	/** Ascending sorted copy. */
	public static function sort(xs:Array<Float>):Array<Float> {
		if (xs == null || xs.length == 0) return [];
		return sortedCopy(xs);
	}

	/** Indices that would sort `xs` ascending (stable for equal values). */
	public static function argsort(xs:Array<Float>):Array<Float> {
		if (xs == null || xs.length == 0) return [];
		var idx:Array<Int> = [for (i in 0...xs.length) i];
		idx.sort(function(i, j) {
			var a = xs[i], b = xs[j];
			if (a < b) return -1;
			if (a > b) return 1;
			return i < j ? -1 : (i > j ? 1 : 0);
		});
		return [for (i in idx) i * 1.0];
	}

	/**
	 * OLS of `xs[i]` against index `i` (0..n-1).
	 * Returns `{slope, intercept, r2}`; NaN fields when n < 2 or x has zero variance.
	 */
	public static function regression(xs:Array<Float>):Dynamic {
		var n = xs == null ? 0 : xs.length;
		if (n < 2) return {slope: Math.NaN, intercept: Math.NaN, r2: Math.NaN};
		var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0, sumYY = 0.0;
		for (i in 0...n) {
			var x = i * 1.0;
			var y = xs[i];
			sumX += x;
			sumY += y;
			sumXX += x * x;
			sumXY += x * y;
			sumYY += y * y;
		}
		var den = n * sumXX - sumX * sumX;
		if (den == 0.0) return {slope: Math.NaN, intercept: Math.NaN, r2: Math.NaN};
		var slope = (n * sumXY - sumX * sumY) / den;
		var intercept = (sumY - slope * sumX) / n;
		var ssTot = sumYY - sumY * sumY / n;
		var r2 = ssTot == 0.0 ? Math.NaN : 1.0 - residualSs(xs, slope, intercept) / ssTot;
		return {slope: slope, intercept: intercept, r2: r2};
	}

	/** Pearson autocorrelation at integer `lag` (>= 1). */
	public static function autocorr(xs:Array<Float>, lag:Int):Float {
		if (xs == null || lag < 1 || xs.length <= lag) return Math.NaN;
		var a:Array<Float> = [];
		var b:Array<Float> = [];
		for (i in 0...(xs.length - lag)) {
			a.push(xs[i]);
			b.push(xs[i + lag]);
		}
		return pearson(a, b);
	}

	/** Population z-scores. A non-empty constant vector maps to all zeros. */
	public static function zScores(xs:Array<Float>):Array<Float> {
		if (xs.length == 0) return [];
		var avg = mean(xs);
		var sd = standardDeviation(xs);
		if (sd == 0.0) return [for (_ in xs) 0.0];
		return [for (x in xs) (x - avg) / sd];
	}

	/** Inclusive cumulative sum, using compensated accumulation. */
	public static function cumulativeSum(xs:Array<Float>):Array<Float> {
		var out:Array<Float> = [];
		var sum = 0.0;
		var correction = 0.0;
		for (x in xs) {
			var next = sum + x;
			if (Math.abs(sum) >= Math.abs(x))
				correction += (sum - next) + x;
			else
				correction += (x - next) + sum;
			sum = next;
			out.push(sum + correction);
		}
		return out;
	}

	/** Consecutive first differences; length is max(0, n - 1). */
	public static function difference(xs:Array<Float>):Array<Float> {
		var out:Array<Float> = [];
		for (i in 1...xs.length) out.push(xs[i] - xs[i - 1]);
		return out;
	}

	/** Min-max normalization to [0, 1]. A constant vector maps to all zeros. */
	public static function normalize(xs:Array<Float>):Array<Float> {
		if (xs.length == 0) return [];
		var lo = xs[0];
		var hi = xs[0];
		for (i in 1...xs.length) {
			if (xs[i] < lo) lo = xs[i];
			if (xs[i] > hi) hi = xs[i];
		}
		var span = hi - lo;
		if (span == 0.0) return [for (_ in xs) 0.0];
		return [for (x in xs) (x - lo) / span];
	}

	static function varianceWithDivisor(xs:Array<Float>, sample:Bool):Float {
		if (xs.length == 0 || (sample && xs.length < 2)) return Math.NaN;
		var avg = 0.0;
		var m2 = 0.0;
		for (i in 0...xs.length) {
			var n = i + 1.0;
			var delta = xs[i] - avg;
			avg += delta / n;
			m2 += delta * (xs[i] - avg);
		}
		return m2 / (sample ? xs.length - 1 : xs.length);
	}

	static function compensatedSum(xs:Array<Float>):Float {
		var sum = 0.0;
		var correction = 0.0;
		for (x in xs) {
			var next = sum + x;
			if (Math.abs(sum) >= Math.abs(x))
				correction += (sum - next) + x;
			else
				correction += (x - next) + sum;
			sum = next;
		}
		return sum + correction;
	}

	static function sortedCopy(xs:Array<Float>):Array<Float> {
		var sorted = xs.copy();
		sorted.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return sorted;
	}

	static function residualSs(xs:Array<Float>, slope:Float, intercept:Float):Float {
		var ss = 0.0;
		for (i in 0...xs.length) {
			var e = xs[i] - (intercept + slope * i);
			ss += e * e;
		}
		return ss;
	}
}
