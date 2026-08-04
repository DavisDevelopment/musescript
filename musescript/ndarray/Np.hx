package musescript.ndarray;

/**
 * Haxe `np.*` facade — thick numpy-feel catalog, zero Dynamic on typed API.
 *
 * Engine eligibility:
 *   Interp — N | JS — B (`np_*`) | WASM — N subset + H escapes (see
 *   `WasmNpEligibility` / docs/WASM_NP.md; vec_* + nd_matmul) | VM — U
 * Accel: pure Haxe f64 default — see `NdAccel.hx`. DetMath for exp/log/pow.
 *
 * M2: strides/views, multi-axis reduce, true Bool masks, bridges via `NdBridge`.
 * Indexing: stepped slices (views), `take` / `gather` / `take_along` (copies).
 * Bool compress stays separate from integer take — see `NdIndex`.
 * M2.5: concrete `NdArrayF32` / `NdArrayI32`; default Muse path stays **F64**.
 */
class Np {
	static inline function empty0():NdArrayF64 return NdArrayF64.empty([0]);
	static inline function orEmpty(r:Null<NdArrayF64>):NdArrayF64 return r != null ? r : empty0();
	static inline function orFalseMask():NdArrayBool return NdArrayBool.empty([0]);
	static inline function orEmptyBool(r:Null<NdArrayBool>):NdArrayBool return r != null ? r : orFalseMask();

	// --- creation ---
	public static inline function zeros(shape:Array<Int>):NdArrayF64 return NdArrayF64.zeros(shape);
	public static inline function ones(shape:Array<Int>):NdArrayF64 return NdArrayF64.ones(shape);
	public static inline function full(shape:Array<Int>, value:Float):NdArrayF64 return NdArrayF64.full(shape, value);
	public static inline function empty(shape:Array<Int>):NdArrayF64 return NdArrayF64.empty(shape);
	public static inline function arange(startOrStop:Float, ?stop:Float, ?step:Float):NdArrayF64
		return NdArrayF64.arange(startOrStop, stop, step);
	public static inline function linspace(start:Float, stop:Float, ?num:Int = 50, ?endpoint:Bool = true):NdArrayF64
		return NdArrayF64.linspace(start, stop, num, endpoint);
	public static inline function eye(n:Int, ?m:Int):NdArrayF64 return NdLinalg.eye(n, m);
	public static inline function identity(n:Int):NdArrayF64 return NdLinalg.identity(n);

	public static inline function asarray(data:Array<Float>, ?shape:Array<Int>):NdArrayF64 {
		if (shape == null) return NdArrayF64.asarray1d(data);
		return orEmpty(NdArrayF64.fromPacked(shape, data));
	}
	public static inline function asarray2d(rows:Array<Array<Float>>):NdArrayF64
		return orEmpty(NdArrayF64.asarray2d(rows));

	/** Explicit F32 / I32 creation — never used by default Muse factories. */
	public static inline function zerosF32(shape:Array<Int>):NdArrayF32 return NdArrayF32.zeros(shape);
	public static inline function onesF32(shape:Array<Int>):NdArrayF32 return NdArrayF32.ones(shape);
	public static inline function fullF32(shape:Array<Int>, value:Float):NdArrayF32 return NdArrayF32.full(shape, value);
	public static inline function emptyF32(shape:Array<Int>):NdArrayF32 return NdArrayF32.empty(shape);
	public static inline function asarrayF32(data:Array<Float>, ?shape:Array<Int>):NdArrayF32 {
		if (data == null) return NdArrayF32.empty([0]);
		var r = NdArrayF32.fromPacked(shape == null ? [data.length] : shape, data);
		return r != null ? r : NdArrayF32.empty([0]);
	}

	public static inline function zerosI32(shape:Array<Int>):NdArrayI32 return NdArrayI32.zeros(shape);
	public static inline function onesI32(shape:Array<Int>):NdArrayI32 return NdArrayI32.ones(shape);
	public static inline function fullI32(shape:Array<Int>, value:Int):NdArrayI32 return NdArrayI32.full(shape, value);
	public static inline function emptyI32(shape:Array<Int>):NdArrayI32 return NdArrayI32.empty(shape);
	public static inline function arangeI32(startOrStop:Int, ?stop:Int, ?step:Int):NdArrayI32
		return NdArrayI32.arange(startOrStop, stop, step);
	public static inline function asarrayI32(data:Array<Int>, ?shape:Array<Int>):NdArrayI32 {
		if (data == null) return NdArrayI32.empty([0]);
		var r = NdArrayI32.fromPacked(shape == null ? [data.length] : shape, data);
		return r != null ? r : NdArrayI32.empty([0]);
	}

	// --- shape ---
	public static inline function reshape(a:NdArrayF64, shape:Array<Int>):NdArrayF64
		return a == null ? empty0() : orEmpty(a.reshape(shape));
	public static inline function transpose(a:NdArrayF64, ?axes:Array<Int>):NdArrayF64
		return a == null ? empty0() : orEmpty(a.transpose(axes));
	public static inline function swapaxes(a:NdArrayF64, i:Int, j:Int):NdArrayF64
		return a == null ? empty0() : orEmpty(a.swapaxes(i, j));
	public static inline function copy(a:NdArrayF64):NdArrayF64
		return a == null ? empty0() : a.copy();
	public static inline function ravel(a:NdArrayF64):NdArrayF64 return NdArrayF64.ravel(a);
	public static inline function flatten(a:NdArrayF64):NdArrayF64 {
		if (a == null) return empty0();
		var c = a.copy();
		return orEmpty(c.reshape([c.size]));
	}
	public static inline function expandDims(a:NdArrayF64, axis:Int):NdArrayF64
		return orEmpty(NdArrayF64.expandDims(a, axis));
	public static inline function squeeze(a:NdArrayF64, ?axis:Int):NdArrayF64
		return NdArrayF64.squeeze(a, axis);
	public static inline function broadcastTo(a:NdArrayF64, shape:Array<Int>):NdArrayF64
		return orEmpty(NdArrayF64.broadcastTo(a, shape));
	public static inline function concatenate(arrays:Array<NdArrayF64>, ?axis:Int = 0):NdArrayF64
		return orEmpty(NdArrayF64.concatenate(arrays, axis));
	public static inline function stack(arrays:Array<NdArrayF64>, ?axis:Int = 0):NdArrayF64
		return orEmpty(NdArrayF64.stack(arrays, axis));

	public static inline function shapeOf(a:NdArrayF64):Array<Int>
		return a == null ? [] : (a.shape : Array<Int>).copy();
	public static inline function ndimOf(a:NdArrayF64):Int return a == null ? 0 : a.ndim;
	public static inline function sizeOf(a:NdArrayF64):Int return a == null ? 0 : a.size;
	public static inline function isCContiguous(a:NdArrayF64):Bool return a != null && a.isCContiguous();

	public static inline function get(a:NdArrayF64, indices:Array<Int>):Float
		return a == null ? Math.NaN : a.getAt(indices);
	public static inline function getFlat(a:NdArrayF64, i:Int):Float
		return a == null ? Math.NaN : a.getFlat(i);
	public static inline function slice(a:NdArrayF64, start:Int, stop:Int, ?step:Int = 1):NdArrayF64
		return a == null ? empty0() : orEmpty(a.slice1d(start, stop, step));
	public static inline function sliceAxis(a:NdArrayF64, axis:Int, start:Int, stop:Int, ?step:Int = 1):NdArrayF64
		return a == null ? empty0() : orEmpty(a.sliceAxis(axis, start, stop, step));

	/** `np.take` — integer gather; OOB → empty. See `NdIndex` for semantics. */
	public static inline function take(a:NdArrayF64, indices:Array<Int>, ?axis:Null<Int>):NdArrayF64
		return orEmpty(NdIndex.take(a, indices, axis));
	public static inline function takeNd(a:NdArrayF64, indices:NdArrayF64, ?axis:Null<Int>):NdArrayF64
		return orEmpty(NdIndex.takeNd(a, indices, axis));
	public static inline function takeI32(a:NdArrayF64, indices:NdArrayI32, ?axis:Null<Int>):NdArrayF64
		return orEmpty(NdIndex.takeI32(a, indices, axis));
	public static inline function gather(a:NdArrayF64, indices:Array<Int>):NdArrayF64
		return orEmpty(NdIndex.gather(a, indices));
	public static inline function gatherNd(a:NdArrayF64, indices:NdArrayF64):NdArrayF64
		return orEmpty(NdIndex.gatherNd(a, indices));
	public static inline function gatherI32(a:NdArrayF64, indices:NdArrayI32):NdArrayF64
		return orEmpty(NdIndex.gatherI32(a, indices));
	public static inline function takeAlong(a:NdArrayF64, indices:NdArrayF64, axis:Int):NdArrayF64
		return orEmpty(NdIndex.takeAlong(a, indices, axis));
	public static inline function takeAlongI32(a:NdArrayF64, indices:NdArrayI32, axis:Int):NdArrayF64
		return orEmpty(NdIndex.takeAlongI32(a, indices, axis));

	/**
	 * dtype cast from F64 → concrete storage.
	 * Returns `AnyNdArray` so `"float32"` / `"int32"` / `"bool"` are real buffers.
	 * See `NdCast` for truncation / promotion rules. Unknown dtype → F64 copy.
	 */
	public static function astype(a:NdArrayF64, dtype:String):AnyNdArray {
		if (a == null) return AnyNdArray.F64(empty0());
		return NdCast.astypeAny(AnyNdArray.F64(a), dtype);
	}

	/** Round-trip cast for any concrete arm. */
	public static function astypeAny(a:AnyNdArray, dtype:String):AnyNdArray {
		if (a == null) return AnyNdArray.F64(empty0());
		return NdCast.astypeAny(a, dtype);
	}

	public static inline function asF32(a:NdArrayF64):NdArrayF32
		return a == null ? NdArrayF32.empty([0]) : NdArrayF32.fromF64(a);
	public static inline function asI32(a:NdArrayF64):NdArrayI32
		return a == null ? NdArrayI32.empty([0]) : NdArrayI32.fromF64(a);
	public static inline function asF64FromF32(a:NdArrayF32):NdArrayF64
		return a == null ? empty0() : a.toF64();
	public static inline function asF64FromI32(a:NdArrayI32):NdArrayF64
		return a == null ? empty0() : a.toF64();

	/** Legacy: `"bool"` migration copy stored as F64 0/1 (prefer `boolFromF64`). */
	public static function astypeF64(a:NdArrayF64, dtype:String):NdArrayF64 {
		if (a == null) return empty0();
		var d = NdDType.parse(dtype);
		if (d == null) return a.copy();
		return switch (d) {
			case F64: a.copy();
			case F32: NdArrayF32.fromF64(a).toF64(); // trunc round-trip
			case I32: NdArrayI32.fromF64(a).toF64();
			case BOOL:
				var out = NdArrayF64.empty(a.shape);
				for (i in 0...a.size) out.setFlat(i, a.getFlat(i) != 0 ? 1.0 : 0.0);
				out;
		};
	}

	// --- typed F32 / I32 ops (see NdTypedOps) ---
	public static inline function addF32(a:NdArrayF32, b:NdArrayF32):NdArrayF32 {
		var r = NdTypedOps.addF32(a, b);
		return r != null ? r : NdArrayF32.empty([0]);
	}
	public static inline function mulF32(a:NdArrayF32, b:NdArrayF32):NdArrayF32 {
		var r = NdTypedOps.mulF32(a, b);
		return r != null ? r : NdArrayF32.empty([0]);
	}
	public static inline function addI32(a:NdArrayI32, b:NdArrayI32):NdArrayI32 {
		var r = NdTypedOps.addI32(a, b);
		return r != null ? r : NdArrayI32.empty([0]);
	}
	public static inline function mulI32(a:NdArrayI32, b:NdArrayI32):NdArrayI32 {
		var r = NdTypedOps.mulI32(a, b);
		return r != null ? r : NdArrayI32.empty([0]);
	}
	public static inline function sumF32(a:NdArrayF32):Float return NdTypedOps.sumF32(a);
	public static inline function sumI32(a:NdArrayI32):Float return NdTypedOps.sumI32(a);
	public static inline function matmulF32(a:NdArrayF32, b:NdArrayF32):NdArrayF32 {
		var r = NdTypedOps.matmulF32(a, b);
		return r != null ? r : NdArrayF32.empty([0]);
	}
	public static inline function matmulI32(a:NdArrayI32, b:NdArrayI32):NdArrayI32 {
		var r = NdTypedOps.matmulI32(a, b);
		return r != null ? r : NdArrayI32.empty([0]);
	}

	/** Existential add (promotion rules in NdCast / NdTypedOps). */
	public static function addAny(a:AnyNdArray, b:AnyNdArray):AnyNdArray {
		var r = NdTypedOps.addAny(a, b);
		return r != null ? r : AnyNdArray.F64(empty0());
	}
	public static function mulAny(a:AnyNdArray, b:AnyNdArray):AnyNdArray {
		var r = NdTypedOps.mulAny(a, b);
		return r != null ? r : AnyNdArray.F64(empty0());
	}

	public static inline function asarrayBool(data:Array<Bool>, ?shape:Array<Int>):NdArrayBool {
		if (data == null) return NdArrayBool.empty([0]);
		return orEmptyBool(NdArrayBool.fromPacked(shape == null ? [data.length] : shape, data));
	}

	public static inline function boolFromF64(a:NdArrayF64):NdArrayBool return NdArrayBool.fromF64(a);
	public static inline function boolToF64(a:NdArrayBool):NdArrayF64
		return a == null ? empty0() : a.toF64();

	// --- ufuncs ---
	public static function add(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.add(a, b));
	public static function subtract(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.subtract(a, b));
	public static function multiply(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.mul(a, b));
	public static function divide(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.divide(a, b));
	public static function power(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.power(a, b));
	public static function minimum(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.minimum(a, b));
	public static function maximum(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdUfuncs.maximum(a, b));
	public static function equal(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.equal(a, b));
	public static function notEqual(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.notEqual(a, b));
	public static function greater(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.greater(a, b));
	public static function greaterEqual(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.greaterEqual(a, b));
	public static function less(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.less(a, b));
	public static function lessEqual(a:NdArrayF64, b:NdArrayF64):NdArrayBool return orEmptyBool(NdUfuncs.lessEqual(a, b));
	public static function negative(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.neg(a);
	public static function abs(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.abs(a);
	public static function sqrt(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.sqrt(a);
	public static function exp(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.exp(a);
	public static function log(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.log(a);
	public static function square(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.square(a);
	public static function sign(a:NdArrayF64):NdArrayF64 return a == null ? empty0() : NdUfuncs.sign(a);
	public static function clip(a:NdArrayF64, lo:Float, hi:Float):NdArrayF64
		return a == null ? empty0() : NdUfuncs.clip(a, lo, hi);
	public static function where(cond:NdArrayF64, x:NdArrayF64, y:NdArrayF64):NdArrayF64
		return orEmpty(NdUfuncs.where(cond, x, y));
	public static function whereBool(cond:NdArrayBool, x:NdArrayF64, y:NdArrayF64):NdArrayF64
		return orEmpty(NdUfuncs.whereBool(cond, x, y));
	public static function compress(a:NdArrayF64, mask:NdArrayBool):NdArrayF64
		return orEmpty(NdUfuncs.compress(a, mask));
	public static function assignWhere(a:NdArrayF64, mask:NdArrayBool, values:NdArrayF64):Bool
		return NdUfuncs.assignWhere(a, mask, values);

	// --- reductions ---
	public static inline function sum(a:NdArrayF64):Float return a == null ? Math.NaN : NdReductions.sumAll(a);
	public static inline function mean(a:NdArrayF64):Float return a == null ? Math.NaN : NdReductions.meanAll(a);
	public static inline function min(a:NdArrayF64):Float return a == null ? Math.NaN : NdReductions.minAll(a);
	public static inline function max(a:NdArrayF64):Float return a == null ? Math.NaN : NdReductions.maxAll(a);
	public static inline function prod(a:NdArrayF64):Float return a == null ? Math.NaN : NdReductions.prodAll(a);
	public static inline function std(a:NdArrayF64, ?ddof:Int = 0):Float
		return a == null ? Math.NaN : NdReductions.stdAll(a, ddof);
	public static inline function variance(a:NdArrayF64, ?ddof:Int = 0):Float
		return a == null ? Math.NaN : NdReductions.varAll(a, ddof);
	public static inline function any(a:NdArrayF64):Bool return a != null && NdReductions.anyAll(a);
	public static inline function all(a:NdArrayF64):Bool return a != null && NdReductions.allAll(a);

	public static function sumAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.sumAxis(a, axis, keepdims));
	public static function meanAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.meanAxis(a, axis, keepdims));
	public static function minAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.minAxis(a, axis, keepdims));
	public static function maxAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.maxAxis(a, axis, keepdims));
	public static function prodAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.prodAxis(a, axis, keepdims));
	public static function stdAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false, ?ddof:Int = 0):NdArrayF64
		return orEmpty(NdReductions.stdAxis(a, axis, keepdims, ddof));
	public static function varAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false, ?ddof:Int = 0):NdArrayF64
		return orEmpty(NdReductions.varAxis(a, axis, keepdims, ddof));
	public static function anyAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayBool
		return orEmptyBool(NdReductions.anyAxis(a, axis, keepdims));
	public static function allAxis(a:NdArrayF64, axis:Int, ?keepdims:Bool = false):NdArrayBool
		return orEmptyBool(NdReductions.allAxis(a, axis, keepdims));

	public static function sumAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.sumAxes(a, axes, keepdims));
	public static function meanAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.meanAxes(a, axes, keepdims));
	public static function minAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.minAxes(a, axes, keepdims));
	public static function maxAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.maxAxes(a, axes, keepdims));
	public static function prodAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayF64
		return orEmpty(NdReductions.prodAxes(a, axes, keepdims));
	public static function stdAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false, ?ddof:Int = 0):NdArrayF64
		return orEmpty(NdReductions.stdAxes(a, axes, keepdims, ddof));
	public static function varAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false, ?ddof:Int = 0):NdArrayF64
		return orEmpty(NdReductions.varAxes(a, axes, keepdims, ddof));
	public static function anyAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayBool
		return orEmptyBool(NdReductions.anyAxes(a, axes, keepdims));
	public static function allAxes(a:NdArrayF64, axes:Array<Int>, ?keepdims:Bool = false):NdArrayBool
		return orEmptyBool(NdReductions.allAxes(a, axes, keepdims));

	public static inline function cumsum(a:NdArrayF64, ?axis:Int = -1):NdArrayF64
		return a == null ? empty0() : NdReductions.cumsum(a, axis);
	public static inline function diff(a:NdArrayF64):NdArrayF64
		return a == null ? empty0() : NdReductions.diff(a);

	// --- linalg ---
	public static function matmul(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdLinalg.matmul(a, b));
	public static function dot(a:NdArrayF64, b:NdArrayF64):Float return NdLinalg.dotScalar(a, b);
	public static function outer(a:NdArrayF64, b:NdArrayF64):NdArrayF64 return orEmpty(NdLinalg.outer(a, b));

	// --- risk / sizing (f64; DetMath log-returns; OrderSim still clamps at fill) ---
	public static function volTargetQty(
		vol:NdArrayF64,
		targetVol:Float,
		base:NdArrayF64,
		?maxQty:Float,
		?minQty:Float,
		?eps:Float
	):NdArrayF64
		return orEmpty(NdRisk.volTargetQty(vol, targetVol, base, maxQty, minQty, eps));

	public static function rollingLogVol(prices:NdArrayF64, window:Int, ?ddof:Int = 0):NdArrayF64
		return orEmpty(NdRisk.rollingLogVol(prices, window, ddof));

	public static function volTargetQtyFromPrices(
		prices:NdArrayF64,
		targetVol:Float,
		base:NdArrayF64,
		window:Int,
		?maxQty:Float,
		?minQty:Float,
		?eps:Float
	):NdArrayF64
		return orEmpty(NdRisk.volTargetQtyFromPrices(prices, targetVol, base, window, maxQty, minQty, eps));

	public static function maskQty(
		mask:NdArrayBool,
		base:NdArrayF64,
		?maxQty:Float,
		?minQty:Float
	):NdArrayF64
		return orEmpty(NdRisk.maskQty(mask, base, maxQty, minQty));
}
