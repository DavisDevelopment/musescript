package musescript.evo;

import musescript.harness.Bar;

/**
 * Closed typed palette mirrored from musegene/palette.py.
 *
 * Host vs genome: authored strategies may call the open `muse.*` host stdlib
 * (`muse.fund.of`, `muse.orders.long`, …). Genome Expand / NMA / Variation use
 * `FIELDS` (OHLCV) plus, when the eval tape carries matching `Bar.data` keys,
 * the gated `AUX_FIELDS` catalog via `fieldsFor` / `Variation.setFieldPool`.
 * Strategies and evo only read pre-joined aux series — no live EDGAR/I/O.
 * Loader → `Bar.data` → WASM `configure_tape`/`configure_features` (or
 * NmaFitness column materialization) → native/interp read. Live SEC/EDGAR
 * fetch stays outside strategy runtime.
 *
 * Expanding the aux catalog further: (1) add names to AUX_FIELDS, (2) Expand
 * already emits bare field idents, (3) NmaFitness + StrategyWasmBackend pack
 * `Bar.data` into tape columns, (4) keep Expand+fitness+WASM regression tests green.
 *
 * Panel genomes v0: `Variation.configureForUniverse(syms)` gates `SPanel` growth
 * so Expand emits literal `close_of`/`mom_of`/`fund_of` for a fixed universe
 * (WASM panel packing), not opaque `dict_new` / bag scaffolding.
 * Panel genomes v1: same gate also grows constrained `PanelAction` templates
 * (`PABuy` / `PARebalance` / `PATargetWeight`) so Expand emits HostABI
 * `buy`/`sell_all`/`rebalance_equal`/`target_weight` instead of `long`/`short`/`flat`.
 * Under `configureForPd` + universe: also closed rank→bag templates
 * (`PABagScanTop` / `PABagRankWeights`) → `bag_from_scan` / `bag_norm(bag_from_dict(ranks))`
 * + `portfolio_apply` (no open `bag_rank_*` / `symbols()` loops). Closed bags are
 * WASM HostABI (`apply_bag_*`); open bags stay escape/U. Fitness uses `runPanelBacktest`.
 * Fitness: attach a `PanelFeed` (`Fitness.configurePanel` /
 * `EvolutionEngine.configureForPanel`) so `PanelAction` genomes score via
 * portfolio `runPanelBacktest` — not single-name Sharpe dressed up. Columnar NMA
 * (cliff 3) hosts closed `SPanel` → `field@SYM` + `PABuy`/`PARebalance`/`PATargetWeight`
 * / closed `PABagScanTop` / `PABagRankWeights` (`preferNma` → backend `nma`); open panel /
 * `KPd` stay Expand (`nma-unsupported`).
 * Open-world bag recipes / `symbols()` remain out of genome Expand.
 *
 * Closed NP / PD palette (not open-world muse.np / muse.pd in Expand):
 * `Variation.configureForNp` / `configureForPd` gate `KNp` / `KPd` growth
 * analogous to AUX_FIELDS + tape presence. Default off ⇒ single-name genomes
 * unchanged. NP Expand emits size-capped `np_mean`/`np_sum`/`np_dot` (WASM may
 * claim native on that scalar subset). PD Expand (`xs_rank`) prefers packed
 * percentile `pd_rank1d` when `|universe| ≤ PD_RANK1D_MAX` (WASM `$vec_rank_pct`
 * path); wider universes keep one-row frame `pd_xs_rank` (opaque U) — no
 * groupby/merge/HTTP. Coerces `KPd` xs_rank onto `PanelAction` / `target_weight`
 * so fitness uses `configureForPanel` → `runPanelBacktest`. Size-safe `pd_shift`
 * grows without a universe and stays single-name. NMA columnarizes closed NP
 * window reduces and cliff-3 closed SPanel/HostABI + bag templates (`PABagScanTop` /
 * `PABagRankWeights`); PD `KPd` stays `nma-unsupported`. Bytecode VM: closed NP scalar B
 * (`VmNpEligibility`), PD `vm-unsupported`. Enable trio: `configureForPanel` +
 * `configureForPd` + `configureForUniverse` (panel configures universe automatically).
 */
class Palette {
	public static final FIELDS:Array<String> = ["open", "high", "low", "close", "volume"];

	/**
	 * Fundamentals / aux series allowed into genomes when present on the tape.
	 * Order is load-bearing for deterministic `fieldsFor` appends.
	 */
	public static final AUX_FIELDS:Array<String> = [
		"revenue", "pe", "eps", "sentiment", "market_cap", "book_value", "dividend_yield"
	];

	/**
	 * Closed NP ops for `KNp` when `Variation.configureForNp` opens the gate.
	 * Order is load-bearing for deterministic catalog / docs.
	 */
	public static final NP_OPS:Array<String> = ["mean", "dot", "sum"];
	/**
	 * Closed PD ops for `KPd` when `configureForPd` (+ universe for `xs_rank`).
	 * No open groupby/merge — `xs_rank` packs scores → `pd_rank1d` when
	 * `|universe| ≤ PD_RANK1D_MAX`, else one-row frame `pd_xs_rank`;
	 * `shift` is size-capped Series lag (`window` ≤ NP_MAX_WIN). Fitness: pair
	 * `xs_rank` with `configureForPanel` so Expand→`target_weight` / closed bags
	 * scores via portfolio `runPanelBacktest`.
	 */
	public static final PD_OPS:Array<String> = ["xs_rank", "shift"];
	/**
	 * Closed bag-scan top-k pool (clamped to `|universe|` at grow/Expand time).
	 * Order is load-bearing for deterministic growth.
	 */
	public static final PD_BAG_TOP_KS:Array<Int> = [1, 2, 3, 5];
	/**
	 * Max universe width for Expand→`pd_rank1d` (mirror of
	 * `WasmPdEligibility.MAX_VEC_LEN`). Larger → frame `pd_xs_rank`.
	 */
	public static final PD_RANK1D_MAX:Int = 64;
	/**
	 * Max shift periods for `KPd("shift")` (leaves room for a size-safe window).
	 */
	public static final PD_SHIFT_MAX:Int = 34;
	/**
	 * Max `window(...)` length for NP genomes (≤ WasmNpEligibility.MAX_VEC_LEN).
	 * WINDOWS entries above this are filtered out of NP growth.
	 */
	public static final NP_MAX_WIN:Int = 55;

	public static final INDS:Array<String> = [
		"sma", "ema", "rsi", "atr", "wma", "rma", "stdev",
		"highest", "lowest", "mom", "roc", "change"
	];
	/**
	 * Panel-of indicator kinds Expand emits as `mom_of`/`sma_of`/`ema_of`/`rsi_of`
	 * (WASM-native on literal symbols). OHLCV panel kinds reuse `FIELDS`.
	 */
	public static final PANEL_OF_INDS:Array<String> = ["mom", "sma", "ema", "rsi"];
	public static final WINDOWS:Array<Int> = [2, 3, 5, 8, 13, 21, 34, 55, 89];
	public static final ARITH:Array<String> = ["+", "-", "*", "min", "max"];
	public static final CMP:Array<String> = [">", "<", ">=", "<="];
	public static final CROSS:Array<String> = ["over", "under"];

	/** WINDOWS entries allowed as NP operand lengths (≤ NP_MAX_WIN). */
	public static function npWindows():Array<Int> {
		return [for (w in WINDOWS) if (w > 0 && w <= NP_MAX_WIN) w];
	}

	/** WINDOWS entries allowed as `pd_shift` periods (1..PD_SHIFT_MAX, < NP_MAX_WIN). */
	public static function pdShiftPeriods():Array<Int> {
		return [for (w in WINDOWS) if (w > 0 && w <= PD_SHIFT_MAX && w < NP_MAX_WIN) w];
	}

	/**
	 * Filter requested NP ops against `NP_OPS`. Null ⇒ full catalog; empty ⇒ off.
	 */
	public static function npOpsFor(?requested:Array<String>):Array<String> {
		if (requested == null) return NP_OPS.copy();
		if (requested.length == 0) return [];
		var hit = new Map<String, Bool>();
		for (r in requested) hit.set(r, true);
		return [for (o in NP_OPS) if (hit.exists(o)) o];
	}

	/**
	 * Filter requested PD ops against `PD_OPS`. Null ⇒ full catalog; empty ⇒ off.
	 */
	public static function pdOpsFor(?requested:Array<String>):Array<String> {
		if (requested == null) return PD_OPS.copy();
		if (requested.length == 0) return [];
		var hit = new Map<String, Bool>();
		for (r in requested) hit.set(r, true);
		return [for (o in PD_OPS) if (hit.exists(o)) o];
	}

	/**
	 * Field pool for genome growth: OHLCV always, plus each `AUX_FIELDS` name
	 * that appears in `present` (typically `auxPresentOn(bars)`). Null/empty
	 * `present` ⇒ OHLCV-only (prior behavior).
	 */
	public static function fieldsFor(?present:Array<String>):Array<String> {
		if (present == null || present.length == 0) return FIELDS.copy();
		var hit = new Map<String, Bool>();
		for (p in present) hit.set(p, true);
		var out = FIELDS.copy();
		for (a in AUX_FIELDS) {
			if (hit.exists(a)) out.push(a);
		}
		return out;
	}

	/** Sorted unique `Bar.data` keys across `bars` (PIT-joined aux only). */
	public static function auxPresentOn(bars:Array<Bar>):Array<String> {
		if (bars == null || bars.length == 0) return [];
		var seen = new Map<String, Bool>();
		for (b in bars) {
			if (b.data == null) continue;
			for (k in b.data.keys()) seen.set(k, true);
		}
		var out = [for (k in seen.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	public static function toJson():Dynamic {
		return {
			schema: "musegene.palette/1",
			id: "musegene.bar-v1",
			fields: FIELDS,
			auxFields: AUX_FIELDS,
			npOps: NP_OPS,
			pdOps: PD_OPS,
			pdRank1dMax: PD_RANK1D_MAX,
			pdShiftMax: PD_SHIFT_MAX,
			npMaxWin: NP_MAX_WIN,
			panelOfInds: PANEL_OF_INDS,
			windows: WINDOWS,
			indicators: INDS,
			arith: ARITH,
			cmp: CMP,
			cross: CROSS,
			limits: { maxDepth: 6, maxNodes: 256 }
		};
	}
}
