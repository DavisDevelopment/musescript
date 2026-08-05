package musescript.vm;

/**
 * Honest bytecode-VM eligibility for `muse.np` / flat `np_*` (after MuseHostLower).
 *
 * Twin of `WasmNpEligibility`, but tags map to the Tier-A unboxed stack:
 *   **B** — `CALL_BUILTIN` returning Float/Bool onto the numeric lanes
 *   **H** — OBJ-lane heap handle (`window` → `Array<Float>`; ND create / vec ufuncs /
 *           reshape → contiguous `NdArrayF64`). Never Dynamic soup on the **nums** lane
 *   **U** — `VmUnsupported` → Expand→interp (unsupported / over-cap / non-1-D create /
 *           axis·keepdims / open HOST_ESCAPE twin)
 *
 * Cliff 2 handle ABI: short contiguous F64 pipelines stay on the VM —
 * create / same-length ufuncs / cumsum·diff / DetMath exp·log / capped matmul /
 * reshape / unary·pairwise ufuncs / clip → reduce/extract
 * (`np_mean` / `np_sum` / `np_min`/`max`/`prod`/`std`/`var` / `np_size`/`ndim` /
 * `np_get_flat` / `np_dot`). Cap `len ≤ 64`, matmul side ≤ 8; runtime-element
 * `asarray([close,…])` allowed. WASM twin is packed `(base,len)` in `VEC_SCRATCH`
 * (see docs/WASM_NP.md).
 *
 * Source of truth for `musescript/vm/README.md` + `docs/WASM_NP.md` VM column +
 * TestBytecodeVmParity.
 */
class VmNpEligibility {
	/** Max 1-D length accepted on the VM ND-handle path (≤ WasmNpEligibility.MAX_VEC_LEN). */
	public static inline var MAX_WIN = 64;
	/** Max side for each of m, n, p in `np_matmul` (＝ WasmNpEligibility.MAX_MATMUL_SIDE). */
	public static inline var MAX_MATMUL_SIDE = 8;

	/**
	 * Scalar-returning ops eligible as **B** (`CALL_BUILTIN` → Float).
	 * Closed evo palette (`Palette.NP_OPS`) subset + cliff-2 `get_flat` + WASM
	 * `NATIVE_SCALAR` twin (bare min/max/prod/std/var/size/ndim; axis·keepdims **U**).
	 */
	public static final SCALAR_B:Array<String> = [
		"np_dot",
		"np_mean",
		"np_sum",
		"np_min",
		"np_max",
		"np_prod",
		"np_std",
		"np_var",
		"np_size",
		"np_ndim",
		"np_get_flat"
	];

	/**
	 * Window heap producer (**H**): returns `Array<Float>` as OBJ-lane temporary
	 * for SCALAR_B args (pre-cliff-2 path; still never on nums).
	 */
	public static final HEAP_PRODUCER:Array<String> = [
		"window"
	];

	/**
	 * Contiguous F64 ND-handle producers / transforms (**H**): return `NdArrayF64`
	 * onto the OBJ lane. Mirrors `WasmNpEligibility.NATIVE_VEC` plus capped `np_reshape`
	 * (WASM reshape stays host_eval **H**; VM twin is CALL_BUILTIN **H**).
	 * Cap `len ≤ MAX_WIN` / matmul side ≤ `MAX_MATMUL_SIDE`; axis·keepdims /
	 * multi-dim create / shaped asarray stay **U**.
	 */
	public static final HEAP_ND:Array<String> = [
		"np_zeros",
		"np_ones",
		"np_full",
		"np_asarray",
		"np_array",
		"np_add",
		"np_subtract",
		"np_multiply",
		"np_divide",
		"np_minimum",
		"np_maximum",
		"np_cumsum",
		"np_diff",
		"np_exp",
		"np_log",
		"np_negative",
		"np_abs",
		"np_sqrt",
		"np_square",
		"np_sign",
		"np_clip",
		"np_matmul",
		"np_reshape"
	];

	/**
	 * Documented **U** catalog (non-exhaustive). Any `np_*` not in SCALAR_B /
	 * HEAP_ND is also unsupported. Kept for honesty tests + docs sync.
	 * Risk helpers + comparisons + residual HOST_ESCAPE twin stay Expand
	 * (wasm-np may host_eval).
	 */
	public static final UNSUPPORTED:Array<String> = [
		"np_empty",
		"np_arange", "np_linspace", "np_eye", "np_identity",
		"np_transpose", "np_swapaxes", "np_copy",
		"np_ravel", "np_flatten", "np_expand_dims", "np_squeeze", "np_broadcast_to",
		"np_concatenate", "np_stack",
		"np_shape", "np_is_c_contiguous",
		"np_get", "np_slice", "np_slice_axis",
		"np_take", "np_gather", "np_take_along",
		"np_astype", "np_bool", "np_bool_to_f64",
		"np_power",
		"np_equal", "np_not_equal", "np_greater", "np_greater_equal",
		"np_less", "np_less_equal",
		"np_where", "np_compress", "np_assign_where",
		"np_any", "np_all",
		"np_outer", "np_to_vector",
		"np_vol_target_qty", "np_mask_qty", "np_rolling_log_vol"
	];

	public static function isScalarB(name:String):Bool
		return SCALAR_B.indexOf(name) >= 0;

	public static function isHeapProducer(name:String):Bool
		return HEAP_PRODUCER.indexOf(name) >= 0;

	public static function isHeapNd(name:String):Bool
		return HEAP_ND.indexOf(name) >= 0;

	public static function isDocumentedUnsupported(name:String):Bool
		return UNSUPPORTED.indexOf(name) >= 0;

	public static function isNpBuiltin(name:String):Bool
		return name != null && StringTools.startsWith(name, "np_");

	/**
	 * True when `name` may emit `CALL_BUILTIN` on the VM.
	 * Non-np/non-window names are left to the pre-existing builtin subset.
	 */
	public static function isVmEligibleBuiltin(name:String):Bool {
		if (isHeapProducer(name)) return true;
		if (isHeapNd(name)) return true;
		if (isNpBuiltin(name)) return isScalarB(name);
		return true; // trade/indicator builtins handled elsewhere
	}

	/**
	 * Arity gate: bare reductions (`np_mean(a)` / `np_sum` / min/max/prod/std/var);
	 * `np_dot(a,b)`; `np_get_flat(a,i)`; `np_size`/`ndim`; create / ufuncs / clip /
	 * reshape as listed. Axis / keepdims / ddof / shaped asarray → **U**.
	 */
	public static function arityOk(name:String, argc:Int):Bool {
		return switch (name) {
			case "np_mean" | "np_sum" | "np_min" | "np_max" | "np_prod"
				| "np_std" | "np_var" | "np_size" | "np_ndim": argc == 1;
			case "np_dot" | "np_get_flat": argc == 2;
			case "window": argc == 2;
			case "np_zeros" | "np_ones" | "np_asarray" | "np_array": argc == 1;
			case "np_full": argc == 2;
			case "np_add" | "np_subtract" | "np_multiply" | "np_divide"
				| "np_minimum" | "np_maximum": argc == 2;
			case "np_cumsum" | "np_diff" | "np_exp" | "np_log"
				| "np_negative" | "np_abs" | "np_sqrt" | "np_square" | "np_sign": argc == 1;
			case "np_clip": argc == 3;
			case "np_matmul" | "np_reshape": argc == 2;
			default: true;
		};
	}

	public static function fitsWin(len:Int):Bool
		return len >= 0 && len <= MAX_WIN;

	public static function fitsMatmulSide(n:Int):Bool
		return n > 0 && n <= MAX_MATMUL_SIDE;
}
