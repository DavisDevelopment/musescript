package musescript.evo;

/**
 * Panel portfolio-action template for Expand (panel genomes v1+).
 *
 * Null/absent on `StrategyGenome` ⇒ classic single-name `long`/`short`/`flat` skeleton
 * (panel genomes v0 predicates-only). When set — typically under
 * `Variation.configureForUniverse` — Expand emits literal HostABI verbs that panel WASM
 * already lowers natively: `buy` / `sell_all` / `target_weight` / `rebalance_equal([...])`
 * and closed `portfolio_apply(bag_from_scan|{bag_norm(bag_from_dict)})` HostABI.
 * Score via `Fitness.configurePanel` + portfolio `runPanelBacktest` (not single-name OrderSim).
 *
 * Rank→bag templates (`PABagScanTop` / `PABagRankWeights`) are **closed-palette** only:
 * fixed-universe score object literals + `bag_from_scan` / `bag_from_dict`+`bag_norm` →
 * `portfolio_apply`. No `symbols()` loops, no `bag_rank_mom` / `bag_computed` / graph recipes.
 * Closed Expand forms HostABI on WASM (`apply_bag_scan` / `apply_bag_weights`);
 * additional gated literals (`apply_bag_raw` / `apply_bag_equal` / `apply_bag_pair` /
 * bottom scan) also HostABI. Open bags / bag locals stay `PANEL_HOST_ESCAPE` →
 * opaque whole-module / host_eval (honest). Interp/JS fitness OK.
 * NMA (`preferNma`): both bag templates are columnar-fast — `PABagScanTop` (equal bag) and
 * `PABagRankWeights` (percentile xs_rank → `bag_norm` → `applyBag`). Open `bag_rank_*` /
 * `symbols()` stay out of Expand and NMA.
 * Short slot (`entryShort`/`exitShort`) is unused by Expand under these templates.
 */
enum PanelAction {
	/** `buy(sym, size)` on entryLong; `sell_all(sym)` on exitLong. */
	PABuy(sym:String);
	/** `rebalance_equal([syms…])` on entryLong; `sell_all` each on exitLong. */
	PARebalance(syms:Array<String>);
	/** `target_weight(sym, size)` on entryLong; `sell_all(sym)` on exitLong (`size` = weight). */
	PATargetWeight(sym:String);
	/**
	 * Top-k equal bag from a fixed-universe score dict (scan_top semantics):
	 * `portfolio_apply(bag_from_scan({SYM: score…}, topK))`; exit liquidates `syms`.
	 */
	PABagScanTop(kind:String, window:Int, topK:Int, syms:Array<String>);
	/**
	 * Soft weights = L1-normalized percentile ranks of the same score vector:
	 * `portfolio_apply(bag_norm(bag_from_dict({SYM: xs_rank…})))`; exit liquidates `syms`.
	 */
	PABagRankWeights(kind:String, window:Int, syms:Array<String>);
}
