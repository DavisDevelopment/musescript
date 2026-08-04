package musescript.ndarray;

/**
 * Reductions with single / multi-axis and `keepdims` (NumPy-shaped).
 * Honors strides via `getAt` / `getFlat`.
 */
class NdReductions {
	public static function sumAll(a:NdArrayF64):Float {
		var n = a.size;
		if (n == 0) return Math.NaN;
		var s = 0.0;
		for (i in 0...n) s += a.getFlat(i);
		return s;
	}

	public static function meanAll(a:NdArrayF64):Float {
		var n = a.size;
		if (n == 0) return Math.NaN;
		return sumAll(a) / n;
	}

	public static function minAll(a:NdArrayF64):Float {
		var n = a.size;
		if (n == 0) return Math.NaN;
		var m = a.getFlat(0);
		for (i in 1...n) {
			var v = a.getFlat(i);
			if (v < m) m = v;
		}
		return m;
	}

	public static function maxAll(a:NdArrayF64):Float {
		var n = a.size;
		if (n == 0) return Math.NaN;
		var m = a.getFlat(0);
		for (i in 1...n) {
			var v = a.getFlat(i);
			if (v > m) m = v;
		}
		return m;
	}

	public static function prodAll(a:NdArrayF64):Float {
		var n = a.size;
		if (n == 0) return Math.NaN;
		var p = 1.0;
		for (i in 0...n) p *= a.getFlat(i);
		return p;
	}

	public static function anyAll(a:NdArrayF64):Bool {
		for (i in 0...a.size) if (a.getFlat(i) != 0) return true;
		return false;
	}

	public static function allAll(a:NdArrayF64):Bool {
		if (a.size == 0) return true;
		for (i in 0...a.size) if (a.getFlat(i) == 0) return false;
		return true;
	}

	public static function varAll(a:NdArrayF64, ?ddof:Int = 0):Float {
		var n = a.size;
		if (n == 0 || n - ddof <= 0) return Math.NaN;
		var mean = meanAll(a);
		var acc = 0.0;
		for (i in 0...n) {
			var d = a.getFlat(i) - mean;
			acc += d * d;
		}
		return acc / (n - ddof);
	}

	public static function stdAll(a:NdArrayF64, ?ddof:Int = 0):Float {
		var v = varAll(a, ddof);
		return Math.isNaN(v) ? Math.NaN : Math.sqrt(v);
	}

	public static function sumAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, [axis], keepdims, 0.0, (acc, v) -> acc + v, (acc, _) -> acc);

	public static function meanAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, [axis], keepdims, 0.0, (acc, v) -> acc + v, (acc, count) -> acc / count);

	public static function minAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, [axis], keepdims, Math.POSITIVE_INFINITY, (acc, v) -> v < acc ? v : acc, (acc, _) -> acc);

	public static function maxAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, [axis], keepdims, Math.NEGATIVE_INFINITY, (acc, v) -> v > acc ? v : acc, (acc, _) -> acc);

	public static function prodAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, [axis], keepdims, 1.0, (acc, v) -> acc * v, (acc, _) -> acc);

	public static function sumAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, axes, keepdims, 0.0, (acc, v) -> acc + v, (acc, _) -> acc);

	public static function meanAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, axes, keepdims, 0.0, (acc, v) -> acc + v, (acc, count) -> acc / count);

	public static function minAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, axes, keepdims, Math.POSITIVE_INFINITY, (acc, v) -> v < acc ? v : acc, (acc, _) -> acc);

	public static function maxAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, axes, keepdims, Math.NEGATIVE_INFINITY, (acc, v) -> v > acc ? v : acc, (acc, _) -> acc);

	public static function prodAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayF64>
		return reduceAxes(a, axes, keepdims, 1.0, (acc, v) -> acc * v, (acc, _) -> acc);

	public static function stdAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false, ?ddof:Int = 0):Null<NdArrayF64>
		return stdAxes(a, [axis], keepdims, ddof);

	public static function varAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false, ?ddof:Int = 0):Null<NdArrayF64>
		return varAxes(a, [axis], keepdims, ddof);

	public static function varAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false, ?ddof:Int = 0):Null<NdArrayF64> {
		var means = meanAxes(a, axes, true);
		if (means == null) return null;
		var shapeInfo = axisPlan(a, axes, keepdims);
		if (shapeInfo == null) return null;
		var count = shapeInfo.reduceCount;
		if (count - ddof <= 0) return NdArrayF64.full(shapeInfo.outDims, Math.NaN);
		var out = NdArrayF64.zeros(shapeInfo.outDims);
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var coords = [for (_ in 0...ndim) 0];
		function recurse(dim:Int):Void {
			if (dim == ndim) {
				var v = a.getAt(coords);
				var m = means.getAt(mapKeep(coords, shapeInfo.reduceMask, true));
				var d = v - m;
				var oc = mapKeep(coords, shapeInfo.reduceMask, keepdims);
				var prev = outDimsLen0(out) ? out.getFlat(0) : out.getAt(oc);
				if (outDimsLen0(out)) out.setFlat(0, prev + d * d);
				else out.setAt(oc, prev + d * d);
				return;
			}
			for (i in 0...sh[dim]) {
				coords[dim] = i;
				recurse(dim + 1);
			}
		}
		recurse(0);
		var scale = 1.0 / (count - ddof);
		for (i in 0...out.size) out.setFlat(i, out.getFlat(i) * scale);
		return out;
	}

	public static function stdAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false, ?ddof:Int = 0):Null<NdArrayF64> {
		var v = varAxes(a, axes, keepdims, ddof);
		if (v == null) return null;
		for (i in 0...v.size) {
			var x = v.getFlat(i);
			v.setFlat(i, Math.isNaN(x) ? Math.NaN : Math.sqrt(x));
		}
		return v;
	}

	public static function anyAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayBool>
		return anyAxes(a, [axis], keepdims);

	public static function allAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):Null<NdArrayBool>
		return allAxes(a, [axis], keepdims);

	public static function anyAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayBool> {
		var plan = axisPlan(a, axes, keepdims);
		if (plan == null) return null;
		var out = NdArrayBool.zeros(plan.outDims);
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var coords = [for (_ in 0...ndim) 0];
		function recurse(dim:Int):Void {
			if (dim == ndim) {
				if (a.getAt(coords) != 0) {
					var oc = mapKeep(coords, plan.reduceMask, keepdims);
					if (plan.outDims.length == 0) out.setFlat(0, true);
					else out.setAt(oc, true);
				}
				return;
			}
			for (i in 0...sh[dim]) {
				coords[dim] = i;
				recurse(dim + 1);
			}
		}
		recurse(0);
		return out;
	}

	public static function allAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):Null<NdArrayBool> {
		var plan = axisPlan(a, axes, keepdims);
		if (plan == null) return null;
		var out = NdArrayBool.ones(plan.outDims);
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var coords = [for (_ in 0...ndim) 0];
		function recurse(dim:Int):Void {
			if (dim == ndim) {
				if (a.getAt(coords) == 0) {
					var oc = mapKeep(coords, plan.reduceMask, keepdims);
					if (plan.outDims.length == 0) out.setFlat(0, false);
					else out.setAt(oc, false);
				}
				return;
			}
			for (i in 0...sh[dim]) {
				coords[dim] = i;
				recurse(dim + 1);
			}
		}
		recurse(0);
		return out;
	}

	static function outDimsLen0(a:NdArrayF64):Bool return a.ndim == 0;

	static function axisPlan(a:NdArrayF64, axes:Array<Int>, keepdims:Bool):Null<{
		outDims:Array<Int>,
		reduceMask:Array<Bool>,
		reduceCount:Int
	}> {
		if (a == null || axes == null || axes.length == 0) return null;
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var reduceMask = [for (_ in 0...ndim) false];
		var reduceCount = 1;
		for (raw in axes) {
			var ax = raw < 0 ? raw + ndim : raw;
			if (ax < 0 || ax >= ndim || reduceMask[ax]) return null;
			reduceMask[ax] = true;
			reduceCount *= sh[ax];
		}
		var outDims:Array<Int> = [];
		for (i in 0...ndim) {
			if (reduceMask[i]) {
				if (keepdims) outDims.push(1);
			} else outDims.push(sh[i]);
		}
		return {outDims: outDims, reduceMask: reduceMask, reduceCount: reduceCount};
	}

	static function mapKeep(coords:Array<Int>, reduceMask:Array<Bool>, keepdims:Bool):Array<Int> {
		var out:Array<Int> = [];
		for (i in 0...coords.length) {
			if (reduceMask[i]) {
				if (keepdims) out.push(0);
			} else out.push(coords[i]);
		}
		return out;
	}

	public static function reduceAxes(
		a:NdArrayF64,
		axes:Array<Int>,
		keepdims:Bool,
		init:Float,
		fold:Float->Float->Float,
		finalize:Float->Int->Float
	):Null<NdArrayF64> {
		var plan = axisPlan(a, axes, keepdims);
		if (plan == null) return null;
		var out = NdArrayF64.empty(plan.outDims);
		for (i in 0...out.size) out.setFlat(i, init);
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var coords = [for (_ in 0...ndim) 0];

		function recurse(dim:Int):Void {
			if (dim == ndim) {
				var oc = mapKeep(coords, plan.reduceMask, keepdims);
				var oi = outFlatIndex(out, oc);
				var prev = out.getFlat(oi);
				out.setFlat(oi, fold(prev, a.getAt(coords)));
				return;
			}
			for (i in 0...sh[dim]) {
				coords[dim] = i;
				recurse(dim + 1);
			}
		}
		recurse(0);
		for (i in 0...out.size) out.setFlat(i, finalize(out.getFlat(i), plan.reduceCount));
		return out;
	}

	static function outFlatIndex(out:NdArrayF64, coords:Array<Int>):Int {
		if (out.ndim == 0) return 0;
		if (coords.length == 0) return 0;
		var cStr = (out.shape : Shape).cStrides();
		var flat = 0;
		for (i in 0...coords.length) flat += coords[i] * cStr[i];
		return flat;
	}

	// legacy single-axis reduce kept via reduceAxes

	public static function cumsum(a:NdArrayF64, ?axis:Int = -1):NdArrayF64 {
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		if (ndim == 0) return a.copy();
		var ax = axis < 0 ? ndim + axis : axis;
		if (ax < 0 || ax >= ndim) return a.copy();
		var out = NdArrayF64.empty(sh);
		var coords = [for (_ in 0...ndim) 0];
		function recurse(dim:Int):Void {
			if (dim == ndim) {
				var s = 0.0;
				for (k in 0...sh[ax]) {
					coords[ax] = k;
					s += a.getAt(coords);
					out.setAt(coords, s);
				}
				return;
			}
			if (dim == ax) {
				recurse(dim + 1);
				return;
			}
			for (i in 0...sh[dim]) {
				coords[dim] = i;
				recurse(dim + 1);
			}
		}
		recurse(0);
		return out;
	}

	public static function diff(a:NdArrayF64):NdArrayF64 {
		if (a.ndim != 1 || a.size < 1) return NdArrayF64.empty([0]);
		var n = a.size - 1;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) out.setFlat(i, a.getFlat(i + 1) - a.getFlat(i));
		return out;
	}
}
