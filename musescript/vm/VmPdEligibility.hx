package musescript.vm;

/**
 * Honest bytecode-VM eligibility for `muse.pd` / flat `pd_*`.
 *
 * Twin of `WasmPdEligibility`. Tags map to the Tier-A unboxed stack:
 *   **B** — scalar-returning CALL_BUILTIN (none claimed — cell extract uses
 *           `np_get_flat` on the ranked NdArray handle)
 *   **H** — OBJ-lane heap handle: packed `pd_rank1d` → contiguous `NdArrayF64`
 *           (never Dynamic soup on the **nums** lane; never `AnyDataFrame` /
 *           `AnyPdSeries` / `TIndex` on nums)
 *   **U** — `VmUnsupported` → Expand→interp / JS
 *
 * Cliff-PD handle ABI (mirrors WASM `$vec_rank` / `$vec_rank_pct`):
 *   `pd_rank1d(constvec|window|ND-handle [, pct])` → NdArrayF64 on OBJ
 *   → `np_get_flat` / `np_mean` / `np_sum` → Float on nums
 * Cap `len ≤ 64`, 1-D only. Frame construct / groupby / merge / Series shift
 * stay **U**. Closed evo `KPd` Expand still needs panel (`xs_rank`) or Series
 * (`shift`) — Fitness.evaluateVm refuses `KPd` genomes honestly.
 *
 * Source of truth for `musescript/vm/README.md` + `docs/WASM_PD.md` VM column +
 * TestBytecodeVmParity.
 */
class VmPdEligibility {
	/** Max 1-D length accepted on the VM pd_rank1d path (＝ WasmPdEligibility.MAX_VEC_LEN). */
	public static inline var MAX_WIN = 64;

	/**
	 * Scalar-returning pd_* claimed as **B**. Empty — rank cell extract is
	 * `np_get_flat` (VmNpEligibility.SCALAR_B), not a pd_* scalar.
	 */
	public static final SCALAR_B:Array<String> = [];

	/**
	 * Cliff-PD packed rank producer (**H**): returns `NdArrayF64` onto the OBJ
	 * lane. Const 1-D data / window / ND handle only (`len ≤ MAX_WIN`);
	 * descending / frame forms → **U**.
	 */
	public static final HEAP_PD:Array<String> = [
		"pd_rank1d"
	];

	/**
	 * Documented **U** catalog (representative). Any `pd_*` not in HEAP_PD /
	 * SCALAR_B is unsupported. Mirrors WasmPdEligibility.HOST_ESCAPE (+ frame
	 * ops) for honesty sync — `pd_rank1d` is **not** listed here.
	 */
	public static final UNSUPPORTED:Array<String> = [
		"pd_series", "pd_dataframe", "pd_from_columns", "pd_from_ndarray", "pd_empty",
		"pd_shape", "pd_columns", "pd_nrows", "pd_ncols", "pd_index",
		"pd_get", "pd_select", "pd_assign", "pd_drop", "pd_copy", "pd_head", "pd_tail",
		"pd_iloc", "pd_to_ndarray",
		"pd_series_values", "pd_series_name", "pd_series_length",
		"pd_index_kind", "pd_index_range", "pd_index_floats", "pd_index_strings",
		"pd_from_bars", "pd_from_bar_column", "pd_from_panel",
		"pd_reindex", "pd_align", "pd_join", "pd_merge_asof",
		"pd_fillna", "pd_dropna", "pd_isna", "pd_concat", "pd_concat_cols",
		"pd_parse_csv", "pd_read_csv", "pd_read_parquet",
		"pd_groupby_agg", "pd_groupby_transform", "pd_groupby_rank",
		"pd_groupby_mean", "pd_groupby_sum", "pd_groupby_std", "pd_groupby_keys_agg",
		"pd_rank", "pd_xs_rank",
		"pd_pivot", "pd_melt", "pd_corr", "pd_cov",
		"pd_shift", "pd_diff", "pd_pct_change",
		"pd_rolling_mean", "pd_rolling_sum", "pd_rolling_std", "pd_ewm_mean",
		"pd_resample",
		"pd_multi_index", "pd_reset_index", "pd_xs", "pd_get_level_values",
		"pd_get_level_values_str", "pd_index_nlevels",
		"pd_factorize", "pd_index_codes", "pd_index_levels", "pd_multi_index_codes"
	];

	public static function isScalarB(name:String):Bool
		return SCALAR_B.indexOf(name) >= 0;

	public static function isHeapPd(name:String):Bool
		return HEAP_PD.indexOf(name) >= 0;

	public static function isDocumentedUnsupported(name:String):Bool
		return UNSUPPORTED.indexOf(name) >= 0;

	public static function isPdBuiltin(name:String):Bool
		return name != null && StringTools.startsWith(name, "pd_");

	/**
	 * True when `name` may emit `CALL_BUILTIN` on the VM.
	 * Non-pd names are left to NP / trade eligibility.
	 */
	public static function isVmEligibleBuiltin(name:String):Bool {
		if (isHeapPd(name)) return true;
		if (isPdBuiltin(name)) return isScalarB(name);
		return true;
	}

	/**
	 * Arity gate matching WASM claimed-native `pd_rank1d`: data [, pct].
	 * Descending / third-arg form → **U**.
	 */
	public static function arityOk(name:String, argc:Int):Bool {
		return switch (name) {
			case "pd_rank1d": argc >= 1 && argc <= 2;
			default: true;
		};
	}

	public static function fitsWin(len:Int):Bool
		return len >= 0 && len <= MAX_WIN;
}
