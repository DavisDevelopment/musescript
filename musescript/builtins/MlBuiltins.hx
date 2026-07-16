package musescript.builtins;

/**
 * Small dependency-free numeric primitives for evolved strategies.
 *
 * Matrices use packed row-major vectors because MuseScript has no matrix type.
 * Invalid dimensions produce NaN for scalar results and [] for vector results.
 */
class MlBuiltins {
	public static inline var MAX_FIT_FEATURES:Int = 32;
	public static inline var MAX_FIT_ROWS:Int = 4096;

	public static function dot(a:Array<Float>, b:Array<Float>):Float {
		if (!sameNonEmptyLength(a, b)) return Math.NaN;
		var out = 0.0;
		for (i in 0...a.length) {
			if (!Math.isFinite(a[i]) || !Math.isFinite(b[i])) return Math.NaN;
			out += a[i] * b[i];
		}
		return out;
	}

	/** Numerically stable logistic sigmoid. */
	public static function sigmoid(x:Float):Float {
		if (Math.isNaN(x)) return Math.NaN;
		if (x >= 0) {
			var z = Math.exp(-x);
			return 1.0 / (1.0 + z);
		}
		var z = Math.exp(x);
		return z / (1.0 + z);
	}

	/** Stable softmax. Empty or non-finite input returns []. */
	public static function softmax(xs:Array<Float>):Array<Float> {
		if (xs == null || xs.length == 0) return [];
		var max = xs[0];
		for (x in xs) {
			if (!Math.isFinite(x)) return [];
			if (x > max) max = x;
		}
		var out:Array<Float> = [];
		var total = 0.0;
		for (x in xs) {
			var e = Math.exp(x - max);
			out.push(e);
			total += e;
		}
		if (!Math.isFinite(total) || total <= 0) return [];
		for (i in 0...out.length) out[i] /= total;
		return out;
	}

	public static function mse(actual:Array<Float>, predicted:Array<Float>):Float {
		if (!sameNonEmptyLength(actual, predicted)) return Math.NaN;
		var total = 0.0;
		for (i in 0...actual.length) {
			if (!Math.isFinite(actual[i]) || !Math.isFinite(predicted[i])) return Math.NaN;
			var d = actual[i] - predicted[i];
			total += d * d;
		}
		return total / actual.length;
	}

	public static function mae(actual:Array<Float>, predicted:Array<Float>):Float {
		if (!sameNonEmptyLength(actual, predicted)) return Math.NaN;
		var total = 0.0;
		for (i in 0...actual.length) {
			if (!Math.isFinite(actual[i]) || !Math.isFinite(predicted[i])) return Math.NaN;
			total += Math.abs(actual[i] - predicted[i]);
		}
		return total / actual.length;
	}

	public static function linearPredict(features:Array<Float>, weights:Array<Float>, ?bias:Float = 0.0):Float {
		if (!Math.isFinite(bias)) return Math.NaN;
		var weighted = dot(features, weights);
		return Math.isNaN(weighted) ? Math.NaN : weighted + bias;
	}

	/**
	 * Fit ridge regression weights from packed row-major features.
	 *
	 * `packedX.length == y.length * featureCount`; include a constant feature
	 * column when an intercept is desired. The solve is bounded and uses
	 * partial-pivot Gaussian elimination. Invalid or singular input returns [].
	 */
	public static function ridgeFit(
		packedX:Array<Float>,
		y:Array<Float>,
		featureCount:Int,
		?lambda:Float = 1e-6
	):Array<Float> {
		if (packedX == null || y == null
			|| featureCount <= 0 || featureCount > MAX_FIT_FEATURES
			|| y.length == 0 || y.length > MAX_FIT_ROWS
			|| packedX.length != y.length * featureCount
			|| !Math.isFinite(lambda) || lambda < 0)
			return [];

		var system:Array<Array<Float>> = [
			for (_ in 0...featureCount) [for (_ in 0...featureCount + 1) 0.0]
		];
		for (row in 0...y.length) {
			var target = y[row];
			if (!Math.isFinite(target)) return [];
			var base = row * featureCount;
			for (j in 0...featureCount) {
				var xj = packedX[base + j];
				if (!Math.isFinite(xj)) return [];
				system[j][featureCount] += xj * target;
				for (k in 0...featureCount) {
					var xk = packedX[base + k];
					if (!Math.isFinite(xk)) return [];
					system[j][k] += xj * xk;
				}
			}
		}
		for (i in 0...featureCount) system[i][i] += lambda;
		return solve(system, featureCount);
	}

	static function solve(system:Array<Array<Float>>, n:Int):Array<Float> {
		var scale = 0.0;
		for (row in system)
			for (i in 0...n)
				if (Math.abs(row[i]) > scale) scale = Math.abs(row[i]);
		var tolerance = Math.max(1.0, scale) * 1e-12;

		for (col in 0...n) {
			var pivot = col;
			for (row in col + 1...n)
				if (Math.abs(system[row][col]) > Math.abs(system[pivot][col])) pivot = row;
			if (Math.abs(system[pivot][col]) <= tolerance) return [];
			if (pivot != col) {
				var swap = system[col];
				system[col] = system[pivot];
				system[pivot] = swap;
			}
			var divisor = system[col][col];
			for (j in col...n + 1) system[col][j] /= divisor;
			for (row in 0...n) {
				if (row == col) continue;
				var factor = system[row][col];
				if (factor == 0) continue;
				for (j in col...n + 1) system[row][j] -= factor * system[col][j];
			}
		}
		var out = [for (i in 0...n) system[i][n]];
		for (v in out) if (!Math.isFinite(v)) return [];
		return out;
	}

	static function sameNonEmptyLength(a:Array<Float>, b:Array<Float>):Bool {
		return a != null && b != null && a.length > 0 && a.length == b.length;
	}
}
