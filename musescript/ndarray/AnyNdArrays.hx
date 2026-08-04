package musescript.ndarray;

class AnyNdArrays {
	public static inline function ofF64(a:NdArrayF64):AnyNdArray return F64(a);
	public static inline function ofF32(a:NdArrayF32):AnyNdArray return F32(a);
	public static inline function ofI32(a:NdArrayI32):AnyNdArray return I32(a);
	public static inline function ofBool(a:NdArrayBool):AnyNdArray return Bool(a);

	public static function unwrapF64(v:AnyNdArray):Null<NdArrayF64> {
		return switch (v) {
			case F64(a): a;
			case F32(a): a.toF64();
			case I32(a): a.toF64();
			case Bool(b): b.toF64();
		};
	}

	public static function unwrapF32(v:AnyNdArray):Null<NdArrayF32> {
		return switch (v) {
			case F32(a): a;
			case F64(a): NdArrayF32.fromF64(a);
			case I32(a): NdArrayF32.fromI32(a);
			case Bool(b): NdArrayF32.fromBool(b);
		};
	}

	public static function unwrapI32(v:AnyNdArray):Null<NdArrayI32> {
		return switch (v) {
			case I32(a): a;
			case F64(a): NdArrayI32.fromF64(a);
			case F32(a): NdArrayI32.fromF32(a);
			case Bool(b): NdArrayI32.fromBool(b);
		};
	}

	public static function unwrapBool(v:AnyNdArray):Null<NdArrayBool> {
		return switch (v) {
			case Bool(a): a;
			case F64(a): NdArrayBool.fromF64(a);
			case F32(a): NdArrayBool.fromF32(a);
			case I32(a): NdArrayBool.fromI32(a);
		};
	}

	public static function dtype(v:AnyNdArray):String
		return NdCast.dtypeOf(v);

	/** Unwrap concrete payload for Muse Dynamic host (no enum wrapper). */
	public static function unwrap(v:AnyNdArray):Dynamic {
		return switch (v) {
			case F64(a): a;
			case F32(a): a;
			case I32(a): a;
			case Bool(a): a;
		};
	}
}
