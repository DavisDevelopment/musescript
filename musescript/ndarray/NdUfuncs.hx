package musescript.ndarray;

import musescript.ew.mcmc.DetMath;

/**
 * Elementwise ufuncs with NumPy broadcasting (via `Broadcast.planFrom`).
 *
 * Arithmetic `+ − * /` are bitwise-identical across targets.
 * `exp` / `log` / `pow` use `DetMath` for fitness-relevant determinism.
 * Comparisons return **`NdArrayBool`** (M2). Legacy F64 0/1 via `mask.toF64()`.
 */
class NdUfuncs {
	public static function add(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x + y);

	public static function subtract(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x - y);

	public static function mul(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x * y);

	public static function divide(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x / y);

	public static function minimum(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x < y ? x : y);

	public static function maximum(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, (x, y) -> x > y ? x : y);

	public static function power(a:NdArrayF64, b:NdArrayF64):Null<NdArrayF64>
		return binop(a, b, detPow);

	public static function equal(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x == y);

	public static function notEqual(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x != y);

	public static function greater(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x > y);

	public static function greaterEqual(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x >= y);

	public static function less(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x < y);

	public static function lessEqual(a:NdArrayF64, b:NdArrayF64):Null<NdArrayBool>
		return binopBool(a, b, (x, y) -> x <= y);

	public static function neg(a:NdArrayF64):NdArrayF64
		return unary(a, (x) -> -x);

	public static function abs(a:NdArrayF64):NdArrayF64
		return unary(a, (x) -> x < 0 ? -x : x);

	public static function sqrt(a:NdArrayF64):NdArrayF64
		return unary(a, Math.sqrt);

	public static function exp(a:NdArrayF64):NdArrayF64
		return unary(a, DetMath.exp);

	public static function log(a:NdArrayF64):NdArrayF64
		return unary(a, DetMath.log);

	public static function square(a:NdArrayF64):NdArrayF64
		return unary(a, (x) -> x * x);

	public static function sign(a:NdArrayF64):NdArrayF64
		return unary(a, (x) -> x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0));

	public static function clip(a:NdArrayF64, lo:Float, hi:Float):NdArrayF64 {
		return unary(a, (x) -> {
			if (x < lo) return lo;
			if (x > hi) return hi;
			return x;
		});
	}

	/** `where(cond, x, y)` — Bool or F64 truthy (!=0) cond. Broadcasts all three. */
	public static function where(cond:NdArrayF64, x:NdArrayF64, y:NdArrayF64):Null<NdArrayF64> {
		return whereBool(NdArrayBool.fromF64(cond), x, y);
	}

	public static function whereBool(cond:NdArrayBool, x:NdArrayF64, y:NdArrayF64):Null<NdArrayF64> {
		if (cond == null || x == null || y == null) return null;
		var pxy = Broadcast.plan(x.shape, y.shape);
		if (!pxy.ok) return null;
		var p = Broadcast.plan(cond.shape, pxy.outShape);
		if (!p.ok) return null;
		var outShape = p.outShape;
		var out = NdArrayF64.empty(outShape);
		var px = Broadcast.planFrom(x, null, outShape);
		var py = Broadcast.planFrom(y, null, outShape);
		if (!px.ok || !py.ok) return null;
		var cStrides = overlayBool(cond, outShape);
		var n = out.size;
		var ndim = outShape.ndim;
		var outStrides = outShape.cStrides();
		for (flat in 0...n) {
			var rem = flat;
			var cOff = cond.offset;
			var xOff = x.offset;
			var yOff = y.offset;
			for (ax in 0...ndim) {
				var idx = outStrides[ax] == 0 ? 0 : Std.int(rem / outStrides[ax]);
				rem = outStrides[ax] == 0 ? rem : rem % outStrides[ax];
				cOff += idx * cStrides[ax];
				xOff += idx * px.aStrides[ax];
				yOff += idx * py.aStrides[ax];
			}
			out.setFlat(flat, cond.getBuf(cOff) ? x.getBuf(xOff) : y.getBuf(yOff));
		}
		return out;
	}

	static function overlayBool(arr:NdArrayBool, outShape:Shape):Array<Int> {
		var as:Array<Int> = arr.shape;
		var real:Array<Int> = arr.strides;
		var n = outShape.ndim;
		var na = as.length;
		var pad = n - na;
		var out:Array<Int> = [for (_ in 0...n) 0];
		var outDims:Array<Int> = outShape;
		for (i in 0...n) {
			if (i < pad) continue;
			var ai = as[i - pad];
			var rs = real[i - pad];
			out[i] = (ai == 1 && outDims[i] != 1) ? 0 : rs;
		}
		return out;
	}

	public static function addScalar(a:NdArrayF64, s:Float):NdArrayF64
		return unary(a, (x) -> x + s);

	public static function mulScalar(a:NdArrayF64, s:Float):NdArrayF64
		return unary(a, (x) -> x * s);

	public static function binop(
		a:NdArrayF64,
		b:NdArrayF64,
		op:Float->Float->Float
	):Null<NdArrayF64> {
		var plan = Broadcast.planFrom(a, b);
		if (!plan.ok) return null;
		var out = NdArrayF64.empty(plan.outShape);
		return binopInto(a, b, out, op) ? out : null;
	}

	public static function binopBool(
		a:NdArrayF64,
		b:NdArrayF64,
		op:Float->Float->Bool
	):Null<NdArrayBool> {
		var plan = Broadcast.planFrom(a, b);
		if (!plan.ok) return null;
		var out = NdArrayBool.empty(plan.outShape);
		var nOut = out.size;
		if (a.shape.equals(b.shape) && a.shape.equals(out.shape)
			&& a.isCContiguous() && b.isCContiguous() && out.isCContiguous()) {
			for (i in 0...nOut) out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			return out;
		}
		var ndim = plan.outShape.ndim;
		var outStrides = plan.outStrides;
		var aStrides = plan.aStrides;
		var bStrides = plan.bStrides;
		for (flat in 0...nOut) {
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
		return out;
	}

	public static function unary(a:NdArrayF64, op:Float->Float):NdArrayF64 {
		var out = NdArrayF64.empty(a.shape);
		var n = a.size;
		for (i in 0...n) out.setFlat(i, op(a.getFlat(i)));
		return out;
	}

	public static function binopInto(
		a:NdArrayF64,
		b:NdArrayF64,
		out:NdArrayF64,
		op:Float->Float->Float
	):Bool {
		var plan = Broadcast.planFrom(a, b);
		if (!plan.ok) return false;
		if (!plan.outShape.equals(out.shape)) return false;
		var nOut = out.size;
		if (a.shape.equals(b.shape) && a.shape.equals(out.shape)
			&& a.isCContiguous() && b.isCContiguous() && out.isCContiguous()) {
			for (i in 0...nOut) out.setFlat(i, op(a.getFlat(i), b.getFlat(i)));
			return true;
		}
		var ndim = plan.outShape.ndim;
		var outStrides = plan.outStrides;
		var aStrides = plan.aStrides;
		var bStrides = plan.bStrides;
		for (flat in 0...nOut) {
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
		return true;
	}

	/** Boolean indexing compress — `a[mask]` → 1-D of selected elements (same size shapes). */
	public static function compress(a:NdArrayF64, mask:NdArrayBool):Null<NdArrayF64> {
		if (a == null || mask == null) return null;
		if (!(a.shape : Shape).equals(mask.shape)) return null;
		var n = mask.countTrue();
		var out = NdArrayF64.empty([n]);
		var j = 0;
		for (i in 0...a.size) {
			if (mask.getFlat(i)) {
				out.setFlat(j, a.getFlat(i));
				j++;
			}
		}
		return out;
	}

	/** In-place `a[mask] = values` (values broadcast as 1-D length countTrue or scalar-ish 1). */
	public static function assignWhere(a:NdArrayF64, mask:NdArrayBool, values:NdArrayF64):Bool {
		if (a == null || mask == null || values == null) return false;
		if (!(a.shape : Shape).equals(mask.shape)) return false;
		var nTrue = mask.countTrue();
		if (values.size == 1) {
			var v = values.getFlat(0);
			for (i in 0...a.size) if (mask.getFlat(i)) a.setFlat(i, v);
			return true;
		}
		if (values.size != nTrue) return false;
		var j = 0;
		for (i in 0...a.size) {
			if (mask.getFlat(i)) {
				a.setFlat(i, values.getFlat(j));
				j++;
			}
		}
		return true;
	}

	static function detPow(base:Float, exp:Float):Float {
		if (base != base || exp != exp) return Math.NaN;
		if (exp == 0) return 1.0;
		if (base == 0) return exp > 0 ? 0.0 : Math.NaN;
		if (base < 0) {
			var ei = Std.int(exp);
			if (ei != exp) return Math.NaN;
			var r = 1.0;
			var b = base;
			var e = ei < 0 ? -ei : ei;
			for (_ in 0...e) r *= b;
			return ei < 0 ? 1.0 / r : r;
		}
		return DetMath.exp(exp * DetMath.log(base));
	}
}
