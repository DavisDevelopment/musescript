package musescript.evo;

/**
 * Panel portfolio-action template for Expand (panel genomes v1).
 *
 * Null/absent on `StrategyGenome` ⇒ classic single-name `long`/`short`/`flat` skeleton
 * (panel genomes v0 predicates-only). When set — typically under
 * `Variation.configureForUniverse` — Expand emits literal HostABI verbs that panel WASM
 * already lowers natively: `buy` / `sell_all` / `target_weight` / `rebalance_equal([...])`.
 * Score via `Fitness.configurePanel` + portfolio `runPanelBacktest` (not single-name OrderSim).
 *
 * Dynamic bags / `symbols()` / scan-driven rebalances stay out of scope (PANEL_HOST_ESCAPE).
 * Short slot (`entryShort`/`exitShort`) is unused by Expand under these templates.
 */
enum PanelAction {
	/** `buy(sym, size)` on entryLong; `sell_all(sym)` on exitLong. */
	PABuy(sym:String);
	/** `rebalance_equal([syms…])` on entryLong; `sell_all` each on exitLong. */
	PARebalance(syms:Array<String>);
	/** `target_weight(sym, size)` on entryLong; `sell_all(sym)` on exitLong (`size` = weight). */
	PATargetWeight(sym:String);
}
