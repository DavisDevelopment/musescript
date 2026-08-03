package musescript.evo;

enum SeriesNode {
	SPrice(field:String);
	SInd(name:String, field:String, window:Int, ?src:SeriesNode);
	/**
	 * Reference to a fan-reduction series of a named projection the genome declares
	 * (`StrategyGenome.projections`; PROJECTION_COEVOLUTION_PLAN.md §3). `name` is the projection
	 * ("proj_0"), `field` selects the reduction over its Monte-Carlo fan ("p50", "spread", "prob_up",
	 * "mean", "sample_i", …). A leaf like `SPrice`: the whole scalar/bool grammar composes over it,
	 * so the policy can read a forecast anywhere it reads a price or indicator. Columnar NMA does not
	 * evaluate this yet — a genome containing `SProj` takes the Expand→interp fallback (nma-unsupported).
	 */
	SProj(name:String, field:String);
	/**
	 * Literal-symbol panel series for fixed-universe panel genomes v0.
	 * `kind` is an OHLCV field (`close`/`open`/…), an of-indicator (`mom`/`sma`/`ema`/`rsi`),
	 * or `fund`. Expand emits `close_of("AAA")` / `mom_of("AAA", 5)` / `fund_of("AAA", "revenue")`.
	 * `field` is the aux name for `fund` (ignored otherwise). `window` is lookback for OHLCV
	 * (omit/0 = current) or indicator length for mom/sma/ema/rsi. WASM lowers these onto
	 * `field@SYM` feature slots when the symbol is a string literal.
	 */
	SPanel(kind:String, sym:String, ?field:String, ?window:Int);
}
