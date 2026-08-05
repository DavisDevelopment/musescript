package musescript.compile;

/**
 * Honest WASM eligibility for `muse.pd` / flat `pd_*` (after `MuseHostLower`).
 *
 * Tags:
 *   **N** — native WAT on packed contiguous f64 in VEC_SCRATCH
 *   **H** — would be per-statement `host_eval` if emit supported opaque
 *           DataFrame round-trip (not implemented for frame returns)
 *   **U** — unsupported on claimed-native WASM path: builtins returning
 *           `TDataFrame` / `TIndex` (and ineligible Series forms) force
 *           **whole-module fallback** via `isOpaqueObjectType` (same honesty
 *           class as TProbCloud / TBag). Interp / JS remain primary for frames.
 *
 * Grant-gated IO (`pd_read_csv` / `pd_read_parquet`) is **U** on WASM fitness
 * and **U** unless IoGrant on other engines.
 *
 * Source of truth for docs/WASM_PD.md + TestPdM4 eligibility checks.
 *
 * Native **N**:
 *   • `pd_rank1d` — average-tie 1-D rank on scratch ≤64 (`$vec_rank` / `$vec_rank_pct`)
 *   • Series lane — packed twin of `VmPdEligibility` HEAP Series:
 *       `pd_series(constvec|window|ND)` → packed (base,len) Series local
 *       `pd_shift(series [, const periods])` → `$vec_shift` (Series only; frame **U**)
 *       `pd_series_values(series)` → same packed buffer for NP follow-ons
 *     Cap `len ≤ 64`; ctor arity 1 (no index/name); `|periods| ≤ 64`.
 *   • `pd_series_length(series)` → f64 from packed len (**N**); `pd_series_name`
 *     stays **U** (name not stored in packed scratch).
 *
 * Frame ops (`pd_xs_rank`, resample, …) stay H/U / opaque fallback. Expand cell
 * extract uses `np_get_flat` (claimed **N** on WASM when index is const — see
 * `WasmNpEligibility`).
 *
 * Closed evo Expand (gated `KPd("xs_rank")`): packs scores → `pd_rank1d`
 * when `|universe| ≤ MAX_VEC_LEN` so WASM PD genomes can hit this N path;
 * wider universes keep opaque frame `pd_xs_rank`. Gated `KPd("shift")` →
 * Series lane **N** when the Expand chain fits.
 */
class WasmPdEligibility {
	/** Mirror muse.np scratch cap for claimed-native 1-D pd ops. */
	public static inline var MAX_VEC_LEN = 64;

	public static final NATIVE_SCALAR:Array<String> = [
		"pd_series_length"
	];

	/** Vector-producing pd ops claimed **N** (assign / nest via lowerVecOperand). */
	public static final NATIVE_VEC:Array<String> = [
		"pd_rank1d",
		"pd_series",
		"pd_shift",
		"pd_series_values"
	];

	/**
	 * Documented H/U catalog (representative). Any `pd_*` not in NATIVE_* is
	 * escape / unsupported. Kept for honesty tests + docs sync.
	 * Series lane entries are **N** — listed in NATIVE_VEC / NATIVE_SCALAR, not here.
	 */
	public static final HOST_ESCAPE:Array<String> = [
		// construct / inspect (frames / Index; Series name + Str sidecar stay U)
		"pd_dataframe", "pd_from_columns", "pd_from_ndarray", "pd_empty",
		"pd_shape", "pd_columns", "pd_nrows", "pd_ncols", "pd_index",
		"pd_get", "pd_select", "pd_assign", "pd_drop", "pd_copy", "pd_head", "pd_tail",
		"pd_iloc", "pd_to_ndarray",
		"pd_series_name",
		"pd_assign_str", "pd_get_str", "pd_str_values", "pd_has_str", "pd_try_get",
		"pd_index_kind", "pd_index_range", "pd_index_floats", "pd_index_strings",
		"pd_from_bars", "pd_from_bar_column", "pd_from_panel",
		// align / join / asof / na
		"pd_reindex", "pd_align", "pd_join", "pd_merge_asof",
		"pd_fillna", "pd_dropna", "pd_isna", "pd_concat", "pd_concat_cols",
		"pd_parse_csv", "pd_read_csv", "pd_read_parquet",
		// groupby / reshape / corr / windows
		"pd_groupby_agg", "pd_groupby_transform", "pd_groupby_rank",
		"pd_groupby_mean", "pd_groupby_sum", "pd_groupby_std", "pd_groupby_keys_agg",
		"pd_rank", "pd_xs_rank",
		"pd_pivot", "pd_melt", "pd_corr", "pd_cov",
		"pd_diff", "pd_pct_change",
		"pd_rolling_mean", "pd_rolling_sum", "pd_rolling_std", "pd_ewm_mean",
		// M4 frame resample (opaque return → U)
		"pd_resample",
		// MultiIndex lite
		"pd_multi_index", "pd_reset_index", "pd_xs", "pd_get_level_values",
		"pd_get_level_values_str", "pd_index_nlevels",
		"pd_factorize", "pd_index_codes", "pd_index_levels", "pd_multi_index_codes"
	];

	public static function isNativeScalar(name:String):Bool
		return NATIVE_SCALAR.indexOf(name) >= 0;

	public static function isNativeVec(name:String):Bool
		return NATIVE_VEC.indexOf(name) >= 0;

	/** Series-returning NATIVE_VEC (`pd_series` / `pd_shift`). */
	public static function isNativeSeries(name:String):Bool
		return name == "pd_series" || name == "pd_shift";

	public static function isDocumentedEscape(name:String):Bool
		return HOST_ESCAPE.indexOf(name) >= 0;

	/** True for any flat `pd_*` (escape / U unless claimed native). */
	public static function isPdBuiltin(name:String):Bool
		return name != null && StringTools.startsWith(name, "pd_");

	public static function isClaimedNative(name:String):Bool
		return isNativeScalar(name) || isNativeVec(name);

	public static function fitsVecLen(len:Int):Bool
		return len >= 0 && len <= MAX_VEC_LEN;

	/** Shift periods const gate: `|p| ≤ MAX_VEC_LEN` (Series lag within scratch cap). */
	public static function fitsShiftPeriods(p:Int):Bool
		return p >= -MAX_VEC_LEN && p <= MAX_VEC_LEN;

	/**
	 * Arity gates for claimed-native Series / rank ops.
	 * Index/name on `pd_series`; descending / third-arg `pd_rank1d`; frame forms → refuse.
	 */
	public static function arityOk(name:String, argc:Int):Bool {
		return switch (name) {
			case "pd_rank1d": argc >= 1 && argc <= 2;
			case "pd_series": argc == 1;
			case "pd_shift": argc >= 1 && argc <= 2;
			case "pd_series_values" | "pd_series_length": argc == 1;
			default: true;
		};
	}
}
