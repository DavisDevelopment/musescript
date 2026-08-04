package musescript.ndarray;

/**
 * Linear algebra on 1–2D F64 arrays (pure Haxe; no BLAS).
 * `matmul` / `dot` follow NumPy's common 1–2D rules.
 */
class NdLinalg {
	/**
	 * Dot product / matmul for 1–2D:
	 *   - 1D · 1D → 0-d (scalar array)  OR use `dotScalar`
	 *   - 2D @ 1D → 1D
	 *   - 1D @ 2D → 1D
	 *   - 2D @ 2D → 2D
	 * Incompatible → null.
	 */
	public static function matmul(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64> {
		if (a == null || b == null) return null;
		var na = a.ndim;
		var nb = b.ndim;
		if (na == 1 && nb == 1) {
			if (a.size != b.size) return null;
			var s = 0.0;
			for (i in 0...a.size) s += a.getFlat(i) * b.getFlat(i);
			var out = NdArrayF64.empty([]);
			out.setFlat(0, s);
			return out;
		}
		if (na == 2 && nb == 1) {
			var m = shapeAt(a, 0);
			var n = shapeAt(a, 1);
			if (b.size != n) return null;
			var out = NdArrayF64.empty([m]);
			for (i in 0...m) {
				var s = 0.0;
				for (k in 0...n) s += a.get2(i, k) * b.getFlat(k);
				out.setFlat(i, s);
			}
			return out;
		}
		if (na == 1 && nb == 2) {
			var n = a.size;
			var p = shapeAt(b, 1);
			if (shapeAt(b, 0) != n) return null;
			var out = NdArrayF64.empty([p]);
			for (j in 0...p) {
				var s = 0.0;
				for (k in 0...n) s += a.getFlat(k) * b.get2(k, j);
				out.setFlat(j, s);
			}
			return out;
		}
		if (na == 2 && nb == 2) {
			var m = shapeAt(a, 0);
			var n = shapeAt(a, 1);
			var n2 = shapeAt(b, 0);
			var p = shapeAt(b, 1);
			if (n != n2) return null;
			var out = NdArrayF64.empty([m, p]);
			for (i in 0...m)
				for (j in 0...p) {
					var s = 0.0;
					for (k in 0...n) s += a.get2(i, k) * b.get2(k, j);
					out.setAt([i, j], s);
				}
			return out;
		}
		return null;
	}

	/** Classic 1-D dot → Float (NaN on mismatch). */
	public static function dotScalar(a:NdArrayF64, b:NdArrayF64):Float {
		if (a == null || b == null || a.ndim != 1 || b.ndim != 1 || a.size != b.size)
			return Math.NaN;
		var s = 0.0;
		for (i in 0...a.size) {
			var x = a.getFlat(i);
			var y = b.getFlat(i);
			if (!Math.isFinite(x) || !Math.isFinite(y)) return Math.NaN;
			s += x * y;
		}
		return s;
	}

	public static function outer(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64> {
		if (a == null || b == null || a.ndim != 1 || b.ndim != 1) return null;
		var out = NdArrayF64.empty([a.size, b.size]);
		for (i in 0...a.size)
			for (j in 0...b.size)
				out.setAt([i, j], a.getFlat(i) * b.getFlat(j));
		return out;
	}

	public static function eye(n:Int, ?m:Int):NdArrayF64 {
		var rows = n < 0 ? 0 : n;
		var cols = m == null ? rows : (m < 0 ? 0 : m);
		var out = NdArrayF64.zeros([rows, cols]);
		var d = rows < cols ? rows : cols;
		for (i in 0...d) out.setAt([i, i], 1.0);
		return out;
	}

	public static function identity(n:Int):NdArrayF64 return eye(n);

	static inline function shapeAt(a:NdArrayF64, i:Int):Int {
		var sh:Array<Int> = a.shape;
		return sh[i];
	}
}
