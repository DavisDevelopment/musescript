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
}
