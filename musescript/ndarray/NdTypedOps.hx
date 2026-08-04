package musescript.ndarray;

/**
 * F32 / I32 elementwise + reductions + matmul.
 *
 * Kept separate from `NdUfuncs` / `NdReductions` so fancy-index / WASM agents
 * can edit those without thrashing this file.
 *
 * Unsupported edges (return null / empty):
 *   - Mixed-dtype arith without prior promote (callers use `addAny` which promotes)
 *   - I32 true-divide / power / exp / log / sqrt → always via F64 result
 *   - Batch ND matmul (>2D) — same as NdLinalg
 */
class NdTypedOps {
	// --- F32 arith (result F32) ----------------------------------------------

	public static function addF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF32>
		return binopF32(a, b, (x, y) -> x + y);

	public static function subF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF32>
		return binopF32(a, b, (x, y) -> x - y);

	public static function mulF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF32>
		return binopF32(a, b, (x, y) -> x * y);

	public static function divF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF32>
		return binopF32(a, b, (x, y) -> x / y);

	public static function negF32(a:NdArrayF32):NdArrayF32
		return unaryF32(a, (x) -> -x);

	public static function absF32(a:NdArrayF32):NdArrayF32
		return unaryF32(a, (x) -> x < 0 ? -x : x);

	public static function squareF32(a:NdArrayF32):NdArrayF32
		return unaryF32(a, (x) -> x * x);

	/** Transcendentals → F64 (DetMath / fitness parity). */
	public static function expF32(a:NdArrayF32):NdArrayF64
		return NdUfuncs.exp(a.toF64());

	public static function logF32(a:NdArrayF32):NdArrayF64
		return NdUfuncs.log(a.toF64());

	public static function sqrtF32(a:NdArrayF32):NdArrayF64
		return NdUfuncs.sqrt(a.toF64());

	public static function powerF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF64>
		return NdUfuncs.power(a.toF64(), b.toF64());

	public static function equalF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayBool>
		return binopBoolF32(a, b, (x, y) -> x == y);

	public static function greaterF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayBool>
		return binopBoolF32(a, b, (x, y) -> x > y);

	// --- I32 arith (integer; wrap on overflow like Haxe Int) ---------------

	public static function addI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayI32>
		return binopI32(a, b, (x, y) -> x + y);

	public static function subI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayI32>
		return binopI32(a, b, (x, y) -> x - y);

	public static function mulI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayI32>
		return binopI32(a, b, (x, y) -> x * y);

	/** True divide → F64 (NumPy `True` divide). Floor-divide unsupported. */
	public static function divI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayF64>
		return NdUfuncs.divide(a.toF64(), b.toF64());

	public static function negI32(a:NdArrayI32):NdArrayI32
		return unaryI32(a, (x) -> -x);

	public static function absI32(a:NdArrayI32):NdArrayI32
		return unaryI32(a, (x) -> x < 0 ? -x : x);

	public static function squareI32(a:NdArrayI32):NdArrayI32
		return unaryI32(a, (x) -> x * x);

	public static function equalI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayBool>
		return binopBoolI32(a, b, (x, y) -> x == y);

	public static function greaterI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayBool>
		return binopBoolI32(a, b, (x, y) -> x > y);

	public static function expI32(a:NdArrayI32):NdArrayF64
		return NdUfuncs.exp(a.toF64());

	public static function logI32(a:NdArrayI32):NdArrayF64
		return NdUfuncs.log(a.toF64());

	public static function sqrtI32(a:NdArrayI32):NdArrayF64
		return NdUfuncs.sqrt(a.toF64());

	// --- reductions --------------------------------------------------------

	public static function sumF32(a:NdArrayF32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		var s = 0.0;
		for (i in 0...a.size) s += a.getFlat(i);
		return s;
	}

	public static function meanF32(a:NdArrayF32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		return sumF32(a) / a.size;
	}

	public static function minF32(a:NdArrayF32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		var m = a.getFlat(0);
		for (i in 1...a.size) {
			var v = a.getFlat(i);
			if (v < m) m = v;
		}
		return m;
	}

	public static function maxF32(a:NdArrayF32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		var m = a.getFlat(0);
		for (i in 1...a.size) {
			var v = a.getFlat(i);
			if (v > m) m = v;
		}
		return m;
	}

	/** Sum as Float (avoids silent Int overflow for large arrays). */
	public static function sumI32(a:NdArrayI32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		var s = 0.0;
		for (i in 0...a.size) s += a.getFlat(i);
		return s;
	}

	public static function meanI32(a:NdArrayI32):Float {
		if (a == null || a.size == 0) return Math.NaN;
		return sumI32(a) / a.size;
	}

	public static function minI32(a:NdArrayI32):Int {
		if (a == null || a.size == 0) return 0;
		var m = a.getFlat(0);
		for (i in 1...a.size) {
			var v = a.getFlat(i);
			if (v < m) m = v;
		}
		return m;
	}

	public static function maxI32(a:NdArrayI32):Int {
		if (a == null || a.size == 0) return 0;
		var m = a.getFlat(0);
		for (i in 1...a.size) {
			var v = a.getFlat(i);
			if (v > m) m = v;
		}
		return m;
	}

	// --- matmul ------------------------------------------------------------

	public static function matmulF32(a:NdArrayF32, b:NdArrayF32):Null<NdArrayF32> {
		if (a == null || b == null) return null;
		var na = a.ndim;
		var nb = b.ndim;
		if (na == 1 && nb == 1) {
			if (a.size != b.size) return null;
			var s = 0.0;
			for (i in 0...a.size) s += a.getFlat(i) * b.getFlat(i);
			var out = NdArrayF32.empty([]);
			out.setFlat(0, s);
			return out;
		}
		if (na == 2 && nb == 2) {
			var m = (a.shape : Array<Int>)[0];
			var n = (a.shape : Array<Int>)[1];
			var n2 = (b.shape : Array<Int>)[0];
			var p = (b.shape : Array<Int>)[1];
			if (n != n2) return null;
			var out = NdArrayF32.empty([m, p]);
			for (i in 0...m)
				for (j in 0...p) {
					var s = 0.0;
					for (k in 0...n) s += a.get2(i, k) * b.get2(k, j);
					out.setAt([i, j], s);
				}
			return out;
		}
		// fallback via F64 for 1D@2D etc.
		var r = NdLinalg.matmul(a.toF64(), b.toF64());
		return r == null ? null : NdArrayF32.fromF64(r);
	}

	public static function matmulI32(a:NdArrayI32, b:NdArrayI32):Null<NdArrayI32> {
		if (a == null || b == null) return null;
		var na = a.ndim;
		var nb = b.ndim;
		if (na == 1 && nb == 1) {
			if (a.size != b.size) return null;
			var s = 0;
			for (i in 0...a.size) s += a.getFlat(i) * b.getFlat(i);
			var out = NdArrayI32.empty([]);
			out.setFlat(0, s);
			return out;
		}
		if (na == 2 && nb == 2) {
			var m = (a.shape : Array<Int>)[0];
			var n = (a.shape : Array<Int>)[1];
			var n2 = (b.shape : Array<Int>)[0];
			var p = (b.shape : Array<Int>)[1];
			if (n != n2) return null;
			var out = NdArrayI32.empty([m, p]);
			for (i in 0...m)
				for (j in 0...p) {
					var s = 0;
					for (k in 0...n) s += a.get2(i, k) * b.get2(k, j);
					out.setAt([i, j], s);
				}
			return out;
		}
		return null;
	}

	public static function dotF32(a:NdArrayF32, b:NdArrayF32):Float {
		if (a == null || b == null || a.ndim != 1 || b.ndim != 1 || a.size != b.size)
			return Math.NaN;
		var s = 0.0;
		for (i in 0...a.size) s += a.getFlat(i) * b.getFlat(i);
		return s;
	}

	public static function dotI32(a:NdArrayI32, b:NdArrayI32):Int {
		if (a == null || b == null || a.ndim != 1 || b.ndim != 1 || a.size != b.size)
			return 0;
		var s = 0;
		for (i in 0...a.size) s += a.getFlat(i) * b.getFlat(i);
		return s;
	}

	// --- AnyNdArray dispatch -----------------------------------------------

	/**
	 * Binary add with promotion: same dtype stays; mixed → F64.
	 * Bool operands promote to the other side (or F64 if both Bool).
	 */
	public static function addAny(a:AnyNdArray, b:AnyNdArray):Null<AnyNdArray> {
		var d = NdCast.promotePair(a, b);
		return switch (d) {
			case F32:
				var r = addF32(NdCast.toF32(a), NdCast.toF32(b));
				r == null ? null : AnyNdArray.F32(r);
			case I32:
				var r = addI32(NdCast.toI32Arr(a), NdCast.toI32Arr(b));
				r == null ? null : AnyNdArray.I32(r);
			case F64 | BOOL:
				var r = NdUfuncs.add(NdCast.toF64(a), NdCast.toF64(b));
				r == null ? null : AnyNdArray.F64(r);
		};
	}

	public static function mulAny(a:AnyNdArray, b:AnyNdArray):Null<AnyNdArray> {
		var d = NdCast.promotePair(a, b);
		return switch (d) {
			case F32:
				var r = mulF32(NdCast.toF32(a), NdCast.toF32(b));
				r == null ? null : AnyNdArray.F32(r);
			case I32:
				var r = mulI32(NdCast.toI32Arr(a), NdCast.toI32Arr(b));
				r == null ? null : AnyNdArray.I32(r);
			case F64 | BOOL:
				var r = NdUfuncs.mul(NdCast.toF64(a), NdCast.toF64(b));
				r == null ? null : AnyNdArray.F64(r);
		};
	}

	public static function subAny(a:AnyNdArray, b:AnyNdArray):Null<AnyNdArray> {
		var d = NdCast.promotePair(a, b);
		return switch (d) {
			case F32:
				var r = subF32(NdCast.toF32(a), NdCast.toF32(b));
				r == null ? null : AnyNdArray.F32(r);
			case I32:
				var r = subI32(NdCast.toI32Arr(a), NdCast.toI32Arr(b));
				r == null ? null : AnyNdArray.I32(r);
			case F64 | BOOL:
				var r = NdUfuncs.subtract(NdCast.toF64(a), NdCast.toF64(b));
				r == null ? null : AnyNdArray.F64(r);
		};
	}

	/** True divide — I32 pair → F64; F32 pair stays F32; else F64. */
	public static function divAny(a:AnyNdArray, b:AnyNdArray):Null<AnyNdArray> {
		return switch (NdCast.promotePair(a, b)) {
			case F32:
				var r = divF32(NdCast.toF32(a), NdCast.toF32(b));
				r == null ? null : AnyNdArray.F32(r);
			case I32:
				var r = divI32(NdCast.toI32Arr(a), NdCast.toI32Arr(b));
				r == null ? null : AnyNdArray.F64(r);
			case F64 | BOOL:
				var r = NdUfuncs.divide(NdCast.toF64(a), NdCast.toF64(b));
				r == null ? null : AnyNdArray.F64(r);
		};
	}

	public static function matmulAny(a:AnyNdArray, b:AnyNdArray):Null<AnyNdArray> {
		var d = NdCast.promotePair(a, b);
		return switch (d) {
			case F32:
				var r = matmulF32(NdCast.toF32(a), NdCast.toF32(b));
				r == null ? null : AnyNdArray.F32(r);
			case I32:
				var r = matmulI32(NdCast.toI32Arr(a), NdCast.toI32Arr(b));
				r == null ? null : AnyNdArray.I32(r);
			case F64 | BOOL:
				var r = NdLinalg.matmul(NdCast.toF64(a), NdCast.toF64(b));
				r == null ? null : AnyNdArray.F64(r);
		};
	}

	public static function sumAny(a:AnyNdArray):Float {
		return switch (a) {
			case F64(x): NdReductions.sumAll(x);
			case F32(x): sumF32(x);
			case I32(x): sumI32(x);
			case Bool(x): x.countTrue();
		};
	}

	// --- kernels -----------------------------------------------------------

	static function binopF32(a:NdArrayF32, b:NdArrayF32, op:Float->Float->Float):Null<NdArrayF32> {
		if (a == null || b == null) return null;
		var plan = Broadcast.planFromMeta(a.shape, a.strides, b.shape, b.strides);
		if (!plan.ok) return null;
		var out = NdArrayF32.empty(plan.outShape);
		var nOut = out.size;
		if (a.shape.equals(b.shape) && a.shape.equals(out.shape)
			&& a.isCContiguous() && b.isCContiguous()) {
			for (i in 0...nOut) out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			return out;
		}
		walkBinopF32(a, b, out, plan, op);
		return out;
	}

	static function walkBinopF32(
		a:NdArrayF32, b:NdArrayF32, out:NdArrayF32,
		plan:{outShape:Shape, outStrides:Array<Int>, aStrides:Array<Int>, bStrides:Array<Int>, ok:Bool},
		op:Float->Float->Float
	):Void {
		var ndim = plan.outShape.ndim;
		var outStrides = plan.outStrides;
		var aStrides = plan.aStrides;
		var bStrides = plan.bStrides;
		for (flat in 0...out.size) {
			var rem = flat;
			var aOff = a.offset;
			var bOff = b.offset;
			for (ax in 0...ndim) {
				var idx = outStrides[ax] == 0 ? 0 : Std.int(rem / outStrides[ax]);
				rem = outStrides[ax] == 0 ? rem : rem % outStrides[ax];
				aOff += idx * aStrides[ax];
				bOff += idx * bStrides[ax];
			}
			out.setFlat(flat, op(a.getBuf(aOff), b.getBuf(bOff)));
		}
	}

	static function binopBoolF32(a:NdArrayF32, b:NdArrayF32, op:Float->Float->Bool):Null<NdArrayBool> {
		if (a == null || b == null) return null;
		var plan = Broadcast.planFromMeta(a.shape, a.strides, b.shape, b.strides);
		if (!plan.ok) return null;
		var out = NdArrayBool.empty(plan.outShape);
		var nOut = out.size;
		if (a.shape.equals(b.shape) && a.isCContiguous() && b.isCContiguous()) {
			for (i in 0...nOut) out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			return out;
		}
		var ndim = plan.outShape.ndim;
		for (flat in 0...nOut) {
			var rem = flat;
			var aOff = a.offset;
			var bOff = b.offset;
			for (ax in 0...ndim) {
				var idx = plan.outStrides[ax] == 0 ? 0 : Std.int(rem / plan.outStrides[ax]);
				rem = plan.outStrides[ax] == 0 ? rem : rem % plan.outStrides[ax];
				aOff += idx * plan.aStrides[ax];
				bOff += idx * plan.bStrides[ax];
			}
			out.setFlat(flat, op(a.getBuf(aOff), b.getBuf(bOff)));
		}
		return out;
	}

	static function unaryF32(a:NdArrayF32, op:Float->Float):NdArrayF32 {
		var out = NdArrayF32.empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, op(a.getFlat(i)));
		return out;
	}

	static function binopI32(a:NdArrayI32, b:NdArrayI32, op:Int->Int->Int):Null<NdArrayI32> {
		if (a == null || b == null) return null;
		var plan = Broadcast.planFromMeta(a.shape, a.strides, b.shape, b.strides);
		if (!plan.ok) return null;
		var out = NdArrayI32.empty(plan.outShape);
		var nOut = out.size;
		if (a.shape.equals(b.shape) && a.isCContiguous() && b.isCContiguous()) {
			for (i in 0...nOut) out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			return out;
		}
		var ndim = plan.outShape.ndim;
		for (flat in 0...nOut) {
			var rem = flat;
			var aOff = a.offset;
			var bOff = b.offset;
			for (ax in 0...ndim) {
				var idx = plan.outStrides[ax] == 0 ? 0 : Std.int(rem / plan.outStrides[ax]);
				rem = plan.outStrides[ax] == 0 ? rem : rem % plan.outStrides[ax];
				aOff += idx * plan.aStrides[ax];
				bOff += idx * plan.bStrides[ax];
			}
			out.setFlat(flat, op(a.getBuf(aOff), b.getBuf(bOff)));
		}
		return out;
	}

	static function binopBoolI32(a:NdArrayI32, b:NdArrayI32, op:Int->Int->Bool):Null<NdArrayBool> {
		if (a == null || b == null) return null;
		var plan = Broadcast.planFromMeta(a.shape, a.strides, b.shape, b.strides);
		if (!plan.ok) return null;
		var out = NdArrayBool.empty(plan.outShape);
		for (i in 0...out.size) {
			// getFlat is correct for views; ok for size-comparable broadcast same-shape
			if (a.shape.equals(b.shape) && a.shape.equals(out.shape)) {
				out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			} else {
				// fallback slow: recompute offsets
				var rem = i;
				var aOff = a.offset;
				var bOff = b.offset;
				for (ax in 0...plan.outShape.ndim) {
					var idx = plan.outStrides[ax] == 0 ? 0 : Std.int(rem / plan.outStrides[ax]);
					rem = plan.outStrides[ax] == 0 ? rem : rem % plan.outStrides[ax];
					aOff += idx * plan.aStrides[ax];
					bOff += idx * plan.bStrides[ax];
				}
				out.setFlat(i, op(a.getBuf(aOff), b.getBuf(bOff)));
			}
		}
		return out;
	}

	static function unaryI32(a:NdArrayI32, op:Int->Int):NdArrayI32 {
		var out = NdArrayI32.empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, op(a.getFlat(i)));
		return out;
	}
}
