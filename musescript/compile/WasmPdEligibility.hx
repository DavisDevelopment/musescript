package musescript.compile;

/**
 * Honest WASM eligibility for `muse.pd` / flat `pd_*` (after `MuseHostLower`).
 *
 * Tags:
 *   **N** — native WAT (none claimed in M3 — frames are opaque objects)
 *   **H** — would be per-statement `host_eval` if emit supported opaque
 *           DataFrame round-trip (not implemented)
 *   **U** — unsupported on claimed-native WASM path: any builtin returning
 *           `TDataFrame` / `TPdSeries` / `TIndex` forces **whole-module
 *           fallback** via `isOpaqueObjectType` (same honesty class as
 *           TProbCloud / TBag). Interp / JS remain primary.
 *
 * Grant-gated IO (`pd_read_csv`) is **U** on WASM fitness and **U** unless
 * IoGrant on other engines.
 *
 * Source of truth for docs/WASM_PD.md + TestPdM3 eligibility checks.
 * Optional future **N**: 1-D `pd_xs_rank` / `pd_shift` on scratch ≤64 — not
 * shipped; do not claim without emitter + DetMath tests.
 */
class WasmPdEligibility {
	/** No native pd ops in M3. */
	public static final NATIVE_SCALAR:Array<String> = [];
	public static final NATIVE_VEC:Array<String> = [];

	/**
	 * Documented H/U catalog (representative). Any `pd_*` not in NATIVE_* is
	 * escape / unsupported. Kept for honesty tests + docs sync.
	 */
	public static final HOST_ESCAPE:Array<String> = [
		// construct / inspect
		"pd_series", "pd_dataframe", "pd_from_columns", "pd_from_ndarray", "pd_empty",
		"pd_shape", "pd_columns", "pd_nrows", "pd_ncols", "pd_index",
		"pd_get", "pd_select", "pd_assign", "pd_drop", "pd_copy", "pd_head", "pd_tail",
		"pd_iloc", "pd_to_ndarray",
		"pd_series_values", "pd_series_name", "pd_series_length",
		"pd_index_kind", "pd_index_range", "pd_index_floats", "pd_index_strings",
		"pd_from_bars", "pd_from_bar_column", "pd_from_panel",
		// align / join / asof / na
		"pd_reindex", "pd_align", "pd_join", "pd_merge_asof",
		"pd_fillna", "pd_dropna", "pd_isna", "pd_concat", "pd_concat_cols",
		"pd_parse_csv", "pd_read_csv",
		// groupby / reshape / corr / windows
		"pd_groupby_agg", "pd_groupby_transform", "pd_groupby_rank",
		"pd_groupby_mean", "pd_groupby_sum", "pd_groupby_std", "pd_groupby_keys_agg",
		"pd_rank", "pd_xs_rank",
		"pd_pivot", "pd_melt", "pd_corr", "pd_cov",
		"pd_shift", "pd_diff", "pd_pct_change",
		"pd_rolling_mean", "pd_rolling_sum", "pd_rolling_std", "pd_ewm_mean"
	];

	public static function isNativeScalar(name:String):Bool
		return NATIVE_SCALAR.indexOf(name) >= 0;

	public static function isNativeVec(name:String):Bool
		return NATIVE_VEC.indexOf(name) >= 0;

	public static function isDocumentedEscape(name:String):Bool
		return HOST_ESCAPE.indexOf(name) >= 0;

	/** True for any flat `pd_*` (all escape / U until a native subset ships). */
	public static function isPdBuiltin(name:String):Bool
		return name != null && StringTools.startsWith(name, "pd_");

	public static function isClaimedNative(name:String):Bool
		return isNativeScalar(name) || isNativeVec(name);
}
