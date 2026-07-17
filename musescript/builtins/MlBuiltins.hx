package musescript.builtins;

/**
 * Small dependency-free numeric primitives for evolved strategies.
 *
 * Matrix values are JSON-safe `{rows, cols, data}` objects backed by packed
 * row-major vectors. Invalid dimensions produce NaN for scalar results and []
 * for vector results.
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

	public static function matrix(rows:Int, cols:Int, data:Array<Float>):Dynamic {
		if (!validMatrixShape(rows, cols, data)) return {rows: 0, cols: 0, data: []};
		return {rows: rows, cols: cols, data: data.copy()};
	}

	public static function matrixRows(value:Dynamic):Int {
		var m = readMatrix(value);
		return m == null ? 0 : m.rows;
	}

	public static function matrixCols(value:Dynamic):Int {
		var m = readMatrix(value);
		return m == null ? 0 : m.cols;
	}

	public static function matrixData(value:Dynamic):Array<Float> {
		var m = readMatrix(value);
		return m == null ? [] : m.data.copy();
	}

	public static function matrixGet(value:Dynamic, row:Int, col:Int):Float {
		var m = readMatrix(value);
		if (m == null || row < 0 || col < 0 || row >= m.rows || col >= m.cols) return Math.NaN;
		return m.data[row * m.cols + col];
	}

	/** Row-major transpose. Invalid input returns an empty matrix. */
	public static function matrixTranspose(value:Dynamic):Dynamic {
		var m = readMatrix(value);
		if (m == null) return {rows: 0, cols: 0, data: []};
		var out:Array<Float> = [];
		for (c in 0...m.cols)
			for (r in 0...m.rows)
				out.push(m.data[r * m.cols + c]);
		return {rows: m.cols, cols: m.rows, data: out};
	}

	/**
	 * Determinant via partial-pivot Gaussian elimination.
	 * Non-square / invalid / oversized → NaN.
	 */
	public static function matrixDeterminant(value:Dynamic):Float {
		var m = readMatrix(value);
		if (m == null || m.rows != m.cols || m.rows == 0 || m.rows > MAX_FIT_FEATURES)
			return Math.NaN;
		var n = m.rows;
		var a:Array<Array<Float>> = [];
		for (r in 0...n) {
			var row:Array<Float> = [];
			for (c in 0...n) row.push(m.data[r * n + c]);
			a.push(row);
		}
		var det = 1.0;
		var scale = 0.0;
		for (row in a)
			for (v in row)
				if (Math.abs(v) > scale) scale = Math.abs(v);
		var tolerance = Math.max(1.0, scale) * 1e-12;
		for (col in 0...n) {
			var pivot = col;
			for (row in col + 1...n)
				if (Math.abs(a[row][col]) > Math.abs(a[pivot][col])) pivot = row;
			if (Math.abs(a[pivot][col]) <= tolerance) return 0.0;
			if (pivot != col) {
				var swap = a[col];
				a[col] = a[pivot];
				a[pivot] = swap;
				det = -det;
			}
			det *= a[col][col];
			for (row in col + 1...n) {
				var factor = a[row][col] / a[col][col];
				for (j in col...n) a[row][j] -= factor * a[col][j];
			}
		}
		return Math.isFinite(det) ? det : Math.NaN;
	}

	/**
	 * Inverse via Gauss-Jordan on [A|I]. Singular / non-square / invalid → empty matrix.
	 */
	public static function matrixInverse(value:Dynamic):Dynamic {
		var m = readMatrix(value);
		if (m == null || m.rows != m.cols || m.rows == 0 || m.rows > MAX_FIT_FEATURES)
			return {rows: 0, cols: 0, data: []};
		var n = m.rows;
		var a:Array<Array<Float>> = [];
		for (r in 0...n) {
			var row:Array<Float> = [];
			for (c in 0...n) row.push(m.data[r * n + c]);
			for (c in 0...n) row.push(r == c ? 1.0 : 0.0);
			a.push(row);
		}
		var scale = 0.0;
		for (row in a)
			for (i in 0...n)
				if (Math.abs(row[i]) > scale) scale = Math.abs(row[i]);
		var tolerance = Math.max(1.0, scale) * 1e-12;
		for (col in 0...n) {
			var pivot = col;
			for (row in col + 1...n)
				if (Math.abs(a[row][col]) > Math.abs(a[pivot][col])) pivot = row;
			if (Math.abs(a[pivot][col]) <= tolerance) return {rows: 0, cols: 0, data: []};
			if (pivot != col) {
				var swap = a[col];
				a[col] = a[pivot];
				a[pivot] = swap;
			}
			var divisor = a[col][col];
			for (j in 0...(2 * n)) a[col][j] /= divisor;
			for (row in 0...n) {
				if (row == col) continue;
				var factor = a[row][col];
				if (factor == 0) continue;
				for (j in 0...(2 * n)) a[row][j] -= factor * a[col][j];
			}
		}
		var out:Array<Float> = [];
		for (r in 0...n)
			for (c in 0...n) {
				var v = a[r][n + c];
				if (!Math.isFinite(v)) return {rows: 0, cols: 0, data: []};
				out.push(v);
			}
		return {rows: n, cols: n, data: out};
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

	public static function ridgeFitMatrix(matrix:Dynamic, y:Array<Float>, ?lambda:Float = 1e-6):Array<Float> {
		var m = readMatrix(matrix);
		if (m == null) return [];
		return ridgeFit(m.data, y, m.cols, lambda);
	}

	static function validMatrixShape(rows:Int, cols:Int, data:Array<Float>):Bool {
		return data != null
			&& rows > 0 && rows <= MAX_FIT_ROWS
			&& cols > 0 && cols <= MAX_FIT_FEATURES
			&& data.length == rows * cols
			&& finiteVector(data);
	}

	static function readMatrix(value:Dynamic):Null<{rows:Int, cols:Int, data:Array<Float>}> {
		if (value == null || Std.isOfType(value, Array) || !Reflect.isObject(value)) return null;
		if (!Reflect.hasField(value, "rows") || !Reflect.hasField(value, "cols") || !Reflect.hasField(value, "data"))
			return null;
		var rows = Std.int(Reflect.field(value, "rows"));
		var cols = Std.int(Reflect.field(value, "cols"));
		var data:Dynamic = Reflect.field(value, "data");
		if (!Std.isOfType(data, Array)) return null;
		var xs:Array<Float> = cast data;
		if (!validMatrixShape(rows, cols, xs)) return null;
		return {rows: rows, cols: cols, data: xs};
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

	static function finiteVector(xs:Array<Float>):Bool {
		for (x in xs) if (!Math.isFinite(x)) return false;
		return true;
	}
}
