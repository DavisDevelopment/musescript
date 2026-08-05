package musescript.vm;

/**
 * Honest bytecode-VM eligibility for `muse.pd` / flat `pd_*`.
 *
 * Twin of `WasmPdEligibility`. Tags map to the Tier-A unboxed stack:
 *   **B** — scalar-returning CALL_BUILTIN (`pd_nrows`/`pd_ncols` on frames;
 *           `pd_series_length`/`pd_series_name` on Series)
 *   **H** — OBJ-lane heap handle:
 *           • packed `pd_rank1d` → contiguous `NdArrayF64`
 *           • Series lane: `pd_series` / Series-shaped `pd_shift` → host `Series`;
 *             `pd_get` → Series; `pd_series_values` → `NdArrayF64`
 *           • Frame lane: `pd_from_columns` / `pd_xs_rank` / single-key groupby /
 *             `pd_join` / frame-shaped `pd_shift` → host `DataFrame`
 *           Never Dynamic soup on the **nums** lane; never Index / merge_asof /
 *           open MultiIndex on nums
 *   **U** — `VmUnsupported` → Expand→interp / JS
 *
 * Cliff-PD handle ABI:
 *   `pd_rank1d(constvec|window|ND-handle [, pct])` → NdArrayF64 on OBJ
 *   `pd_series(constvec|window|ND-handle [, const index|name [, const name]])`
 *     → Series on OBJ (≤64); index = const F64/Str array matching known data
 *     len, or omitted/`null`; 2-arg bare const string = name-only
 *   `pd_shift(series|frame-handle [, const periods])` → same-kind handle on OBJ
 *   `pd_series_values(series-handle)` → NdArrayF64 on OBJ
 *   `pd_series_length(series)` → Float on nums; `pd_series_name(series)` → String on OBJ
 *   `pd_from_columns({const col: [const…]…})` → DataFrame (nrows/ncols ≤64, arity 1)
 *   `pd_get(frame, const col)` → Series
 *   `pd_xs_rank(frame [, const pct])` → DataFrame (ascending default/true only)
 *   `pd_groupby_{mean,sum,std}(frame, const by)` / `pd_groupby_agg(…, const fn?)`
 *   `pd_join(left, right, const on [, const how])` → DataFrame (no validate)
 *   `pd_nrows` / `pd_ncols`(frame) → Float on nums
 *   → `np_get_flat` / `np_mean` / `np_sum` → Float on nums
 * Cap `len ≤ 64`, 1-D / frame dims. Index-heap ctor index (`pd_index_range`),
 * merge_asof / keys-agg / transform / descending xs_rank stay **U**.
 * Expand `KPd("xs_rank")` still refused in Fitness.evaluateVm (panel honesty);
 * hand-written gated frame shapes may compile.
 *
 * Source of truth for `musescript/vm/README.md` + `docs/WASM_PD.md` VM column +
 * TestBytecodeVmParity.
 */
class VmPdEligibility {
	/** Max 1-D / frame dim accepted on the VM pd handle path (＝ WasmPdEligibility.MAX_VEC_LEN). */
	public static inline var MAX_WIN = 64;

	/**
	 * Scalar-returning pd_* claimed as **B** (Float/String on nums/OBJ).
	 * Cell extract still prefers `np_get_flat` on Series-values / NdArray handles.
	 */
	public static final SCALAR_B:Array<String> = [
		"pd_nrows",
		"pd_ncols",
		"pd_series_length",
		"pd_series_name"
	];

	/**
	 * Cliff-PD packed / Series / Frame producers (**H**): return NdArrayF64,
	 * Series, or DataFrame onto the OBJ lane. Const 1-D data / window / handles
	 * only (`len ≤ MAX_WIN`); descending / Index / over-cap / open forms → **U**.
	 */
	public static final HEAP_PD:Array<String> = [
		"pd_rank1d",
		"pd_series",
		"pd_shift",
		"pd_series_values",
		"pd_from_columns",
		"pd_get",
		"pd_xs_rank",
		"pd_groupby_mean",
		"pd_groupby_sum",
		"pd_groupby_std",
		"pd_groupby_agg",
		"pd_join"
	];

	/**
	 * Documented **U** catalog (representative). Any `pd_*` not in HEAP_PD /
	 * SCALAR_B is unsupported. Mirrors WasmPdEligibility.HOST_ESCAPE (+ frame
	 * remnants) for honesty sync — HEAP_PD / SCALAR_B entries are **not** listed here.
	 */
	public static final UNSUPPORTED:Array<String> = [
		"pd_dataframe", "pd_from_ndarray", "pd_empty",
		"pd_shape", "pd_columns", "pd_index",
		"pd_select", "pd_assign", "pd_drop", "pd_copy", "pd_head", "pd_tail",
		"pd_iloc", "pd_to_ndarray",
		"pd_assign_str", "pd_get_str", "pd_str_values", "pd_has_str", "pd_try_get",
		"pd_index_kind", "pd_index_range", "pd_index_floats", "pd_index_strings",
		"pd_from_bars", "pd_from_bar_column", "pd_from_panel",
		"pd_reindex", "pd_align", "pd_merge_asof",
		"pd_fillna", "pd_dropna", "pd_isna", "pd_concat", "pd_concat_cols",
		"pd_parse_csv", "pd_read_csv", "pd_read_parquet",
		"pd_groupby_transform", "pd_groupby_rank", "pd_groupby_keys_agg",
		"pd_rank",
		"pd_pivot", "pd_melt", "pd_corr", "pd_cov",
		"pd_diff", "pd_pct_change",
		"pd_rolling_mean", "pd_rolling_sum", "pd_rolling_std", "pd_ewm_mean",
		"pd_resample",
		"pd_multi_index", "pd_reset_index", "pd_xs", "pd_get_level_values",
		"pd_get_level_values_str", "pd_index_nlevels",
		"pd_factorize", "pd_index_codes", "pd_index_levels", "pd_multi_index_codes"
	];

	/** Single-key groupby agg fn strings accepted on the VM. */
	public static final GROUPBY_AGG_FNS:Array<String> = [
		"mean", "sum", "min", "max", "count", "std"
	];

	/** `pd_join` how= strings accepted on the VM. */
	public static final JOIN_HOWS:Array<String> = [
		"left", "inner", "outer", "right"
	];

	public static function isScalarB(name:String):Bool
		return SCALAR_B.indexOf(name) >= 0;

	public static function isHeapPd(name:String):Bool
		return HEAP_PD.indexOf(name) >= 0;

	/** Series-returning HEAP_PD (`pd_series` / `pd_get`). Dual `pd_shift` is shape-checked separately. */
	public static function isHeapSeries(name:String):Bool
		return name == "pd_series" || name == "pd_get";

	/** Frame-returning HEAP_PD (construct / xs_rank / groupby / join). Dual `pd_shift` separate. */
	public static function isHeapFrame(name:String):Bool {
		return switch (name) {
			case "pd_from_columns" | "pd_xs_rank"
				| "pd_groupby_mean" | "pd_groupby_sum" | "pd_groupby_std" | "pd_groupby_agg"
				| "pd_join":
				true;
			default:
				false;
		};
	}

	public static function isDocumentedUnsupported(name:String):Bool
		return UNSUPPORTED.indexOf(name) >= 0;

	public static function isPdBuiltin(name:String):Bool
		return name != null && StringTools.startsWith(name, "pd_");

	/**
	 * True when `name` may emit `CALL_BUILTIN` on the VM.
	 * Non-pd names are left to NP / trade eligibility.
	 */
	public static function isVmEligibleBuiltin(name:String):Bool {
		if (isHeapPd(name) || isScalarB(name)) return true;
		if (isPdBuiltin(name)) return false;
		return true;
	}

	/**
	 * Arity gates for claimed-native HEAP_PD / SCALAR_B.
	 * Descending / third-arg `pd_rank1d`; Index-heap ctor index; join validate;
	 * from_columns index/columns; keys-agg → **U**.
	 */
	public static function arityOk(name:String, argc:Int):Bool {
		return switch (name) {
			case "pd_rank1d": argc >= 1 && argc <= 2;
			case "pd_series": argc >= 1 && argc <= 3;
			case "pd_shift": argc >= 1 && argc <= 2;
			case "pd_series_values": argc == 1;
			case "pd_from_columns": argc == 1;
			case "pd_get": argc == 2;
			case "pd_xs_rank": argc >= 1 && argc <= 2;
			case "pd_groupby_mean" | "pd_groupby_sum" | "pd_groupby_std": argc == 2;
			case "pd_groupby_agg": argc >= 2 && argc <= 3;
			case "pd_join": argc >= 3 && argc <= 4;
			case "pd_nrows" | "pd_ncols" | "pd_series_length" | "pd_series_name": argc == 1;
			default: true;
		};
	}

	public static function fitsWin(len:Int):Bool
		return len >= 0 && len <= MAX_WIN;

	/** Shift periods const gate: `|p| ≤ MAX_WIN` (Series/frame lag within handle cap). */
	public static function fitsShiftPeriods(p:Int):Bool
		return p >= -MAX_WIN && p <= MAX_WIN;

	public static function isGroupbyAggFn(fn:String):Bool
		return GROUPBY_AGG_FNS.indexOf(fn) >= 0;

	public static function isJoinHow(how:String):Bool
		return JOIN_HOWS.indexOf(how) >= 0;
}
