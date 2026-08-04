package musescript.ndarray;

/**
 * Dtype casts / promotion for concrete NdArray arms.
 *
 * ## Truncation / promotion rules (documented Muse behavior)
 *
 * | From → To | Rule |
 * |---|---|
 * | * → F64 | Widening copy (`Float` / `Int` / Bool 0\|1). |
 * | * → F32 | IEEE754 **binary32** round via `truncF32` (NaN stays NaN; ±Inf preserved). |
 * | * → I32 | Truncate toward 0 (`Std.int`); **clamp** to `[-2^31, 2^31-1]` (defined; unlike NumPy’s UB wrap). |
 * | * → Bool | Truthy: `v != 0 && v == v` (NaN → false). Bool→numeric is 0/1. |
 *
 * ## Arithmetic promotion (typed ops)
 *
 * - Same dtype stays (F32+F32→F32, I32+I32→I32).
 * - Mixed numeric → promote to **F64** (fitness-safe default).
 * - Transcendentals (`exp`/`log`/`sqrt`/`pow`) and true-divide involving I32 → **F64**.
 * - Default Muse creation (`zeros`/`arange`/…) remains **F64**.
 */
class NdCast {
	static inline var I32_MIN:Int = -2147483648;
	static inline var I32_MAX:Int = 2147483647;

	#if js
	static var _f32scratch:js.lib.Float32Array = new js.lib.Float32Array(1);
	#else
	static var _f32bytes:haxe.io.Bytes = haxe.io.Bytes.alloc(4);
	#end

	/** Round `v` to IEEE754 binary32, return as Haxe Float. */
	public static function truncF32(v:Float):Float {
		if (v != v) return Math.NaN;
		#if js
		_f32scratch[0] = v;
		return _f32scratch[0];
		#else
		_f32bytes.setFloat(0, v);
		return _f32bytes.getFloat(0);
		#end
	}

	/** Float / widened value → int32 with toward-0 trunc + clamp. */
	public static function toI32(v:Float):Int {
		if (v != v) return 0; // NaN → 0 (Muse-defined; NumPy is platform-dependent)
		if (v >= I32_MAX) return I32_MAX;
		if (v <= I32_MIN) return I32_MIN;
		return Std.int(v);
	}

	public static inline function truthyFloat(v:Float):Bool
		return v != 0 && v == v;

	public static function dtypeOf(a:AnyNdArray):NdDType {
		return switch (a) {
			case F64(_): NdDType.F64;
			case F32(_): NdDType.F32;
			case I32(_): NdDType.I32;
			case Bool(_): NdDType.BOOL;
		};
	}

	public static function astypeAny(a:AnyNdArray, dtype:String):AnyNdArray {
		var d = NdDType.parse(dtype);
		if (d == null) return AnyNdArray.F64(toF64(a));
		return switch (d) {
			case F64: AnyNdArray.F64(toF64(a));
			case F32: AnyNdArray.F32(toF32(a));
			case I32: AnyNdArray.I32(toI32Arr(a));
			case BOOL: AnyNdArray.Bool(toBool(a));
		};
	}

	public static function toF64(a:AnyNdArray):NdArrayF64 {
		return switch (a) {
			case F64(x): x.copy();
			case F32(x): x.toF64();
			case I32(x): x.toF64();
			case Bool(x): x.toF64();
		};
	}

	public static function toF32(a:AnyNdArray):NdArrayF32 {
		return switch (a) {
			case F32(x): x.copy();
			case F64(x): NdArrayF32.fromF64(x);
			case I32(x): NdArrayF32.fromI32(x);
			case Bool(x): NdArrayF32.fromBool(x);
		};
	}

	public static function toI32Arr(a:AnyNdArray):NdArrayI32 {
		return switch (a) {
			case I32(x): x.copy();
			case F64(x): NdArrayI32.fromF64(x);
			case F32(x): NdArrayI32.fromF32(x);
			case Bool(x): NdArrayI32.fromBool(x);
		};
	}

	public static function toBool(a:AnyNdArray):NdArrayBool {
		return switch (a) {
			case Bool(x): x.copy();
			case F64(x): NdArrayBool.fromF64(x);
			case F32(x): NdArrayBool.fromF32(x);
			case I32(x): NdArrayBool.fromI32(x);
		};
	}

	/** Homogeneous pair stays; else widen to F64 for mixed arithmetic. */
	public static function promotePair(a:AnyNdArray, b:AnyNdArray):NdDType {
		var da = dtypeOf(a);
		var db = dtypeOf(b);
		if (da == db) return da;
		if (da == NdDType.BOOL) return db == NdDType.BOOL ? NdDType.F64 : db;
		if (db == NdDType.BOOL) return da;
		return NdDType.F64;
	}
}
