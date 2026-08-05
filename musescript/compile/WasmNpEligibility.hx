package musescript.compile;

/**
 * Honest WASM eligibility for `muse.np` / flat `np_*` (after `MuseHostLower`).
 *
 * Tags:
 *   **N** — native WAT on packed contiguous f64 in VEC_SCRATCH (this module)
 *   **H** — per-statement `host_eval` (F1); does not force whole-module fallback
 *   **U** — not claimed (same as H today for WASM emit)
 *
 * Native subset is intentionally small and fail-closed: anything outside the
 * lists, any axis/keepdims form, rank>1 except capped matmul, or size above
 * the caps → `EmitUnsupported` → host_eval. Panel/aux feature packing is
 * unchanged (`PANEL_HOST_ESCAPE` / feature tape).
 *
 * Cliff-2 handle twin: VM stores create results as OBJ-lane `NdArrayF64`
 * (`VmNpEligibility.HEAP_ND`); this module keeps packed `(base,len)` scratch
 * locals — same logical 1-D F64 handle, different encoding (docs/WASM_NP.md).
 *
 * Source of truth for emit gates + docs/WASM_NP.md + TestWasmNp.
 */
class WasmNpEligibility {
	/** Max 1-D length lowered into VEC_SCRATCH for claimed-native ops. */
	public static inline var MAX_VEC_LEN = 64;
	/** Max side length for native `np_matmul` (each of m, n, p). */
	public static inline var MAX_MATMUL_SIDE = 8;

	/**
	 * Scalar-returning ops claimed **N** when operands fit the 1-D scratch
	 * path (array literal / window / vector local / nest of native vec ops).
	 * `np_sum` / `np_mean`: zero-arg form, or literal `axis` ∈ {0,-1} with
	 * `keepdims` absent/false (native operands are always 1-D). Other axes /
	 * keepdims → **H**. `np_get_flat`: literal index into a packed vec.
	 */
	public static final NATIVE_SCALAR:Array<String> = [
		"np_dot",
		"np_mean",
		"np_sum",
		// Const flat index into a packed scratch vec (array lit / window / nest incl. pd_rank1d).
		"np_get_flat"
	];

	/**
	 * Vector-producing ops claimed **N** (assign / nest only). Same-length
	 * 1-D for pairwise ufuncs; no general broadcast.
	 */
	public static final NATIVE_VEC:Array<String> = [
		"np_asarray", "np_array",
		"np_zeros", "np_ones", "np_full",
		"np_add", "np_subtract", "np_multiply", "np_divide",
		"np_cumsum", "np_diff",
		"np_exp", "np_log",
		"np_matmul"
	];

	/**
	 * Documented H/U escape list (non-exhaustive of all np_*; any
	 * unlisted op not in NATIVE_* is also escape). Kept for honesty tests.
	 */
	public static final HOST_ESCAPE:Array<String> = [
		"np_reshape", "np_transpose", "np_swapaxes", "np_copy",
		"np_ravel", "np_flatten", "np_expand_dims", "np_squeeze", "np_broadcast_to",
		"np_concatenate", "np_stack",
		"np_arange", "np_linspace", "np_eye", "np_identity", "np_empty",
		"np_shape", "np_ndim", "np_size", "np_is_c_contiguous",
		"np_get", "np_slice", "np_slice_axis",
		"np_take", "np_gather", "np_take_along",
		"np_astype", "np_bool", "np_bool_to_f64",
		"np_power", "np_minimum", "np_maximum",
		"np_equal", "np_not_equal", "np_greater", "np_greater_equal",
		"np_less", "np_less_equal",
		"np_negative", "np_abs", "np_sqrt", "np_square", "np_sign",
		"np_clip", "np_where", "np_compress", "np_assign_where",
		"np_min", "np_max", "np_prod", "np_std", "np_var", "np_any", "np_all",
		"np_outer", "np_to_vector",
		"np_vol_target_qty", "np_mask_qty", "np_rolling_log_vol"
	];

	public static function isNativeScalar(name:String):Bool
		return NATIVE_SCALAR.indexOf(name) >= 0;

	public static function isNativeVec(name:String):Bool
		return NATIVE_VEC.indexOf(name) >= 0;

	public static function isDocumentedEscape(name:String):Bool
		return HOST_ESCAPE.indexOf(name) >= 0;

	public static function fitsVecLen(len:Int):Bool
		return len >= 0 && len <= MAX_VEC_LEN;

	public static function fitsMatmulSide(n:Int):Bool
		return n > 0 && n <= MAX_MATMUL_SIDE;
}
