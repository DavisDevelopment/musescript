package musescript.evo;

enum ScalarNode {
	KConst(v:Float);
	KParam(idx:Int);
	KArith(op:String, a:ScalarNode, b:ScalarNode);
	KSeries(s:SeriesNode);
	KLookback(s:SeriesNode, n:Int);
	KFeature(name:String);
	/** Scalar counterpart of `BoolNode.BHole` -- see its doc comment. Optional domain/name for author holes. */
	KHole(inner:ScalarNode, ?domain:HoleDomain, ?name:Null<String>);
	/**
	 * Closed gated NP palette leaf (`Palette.NP_OPS`). Grown only when
	 * `Variation.configureForNp` opens the gate — never open-world muse.np trees.
	 * Expand emits size-capped `np_mean` / `np_sum` / `np_dot` over `window(series, w)`.
	 * `b` is required for `dot` (ignored for mean/sum). Columnar NMA evaluates trailing
	 * window reduces over SPrice/SInd columns; WASM may claim native on the scalar subset;
	 * bytecode VM is eligible (`VmNpEligibility`). Closed `KPd("shift")` is likewise
	 * NMA/VM-eligible; packed `KPd("xs_rank")` is NMA-eligible (≤ `PD_RANK1D_MAX`);
	 * wide/frame xs_rank remains Expand-only. VM still refuses panel xs_rank.
	 */
	KNp(op:String, a:SeriesNode, window:Int, ?b:SeriesNode);
	/**
	 * Closed gated PD palette leaf (`Palette.PD_OPS`). Grown only when
	 * `Variation.configureForPd` is open; `xs_rank` also needs a fixed universe —
	 * no open groupby/merge/HTTP. Expand emits size-capped `pd_rank1d` (pct) when
	 * `|syms| ≤ PD_RANK1D_MAX`, else one-row `pd_from_columns` + percentile
	 * `pd_xs_rank` (coerces onto `PanelAction` / `target_weight`), or size-capped
	 * `pd_shift` over `window(field, w)`. WASM: `pd_rank1d` N ≤64; frame path U.
	 * NMA: `KPd("shift")` columnar (lookback); packed `xs_rank` columnar when
	 * `|syms| ≤ PD_RANK1D_MAX` (`field@SYM` scores); wide/frame `nma-unsupported`.
	 * VM: Series shift H (`VmPdEligibility`); panel xs_rank U (do not force preferVm).
	 */
	KPd(op:String, kind:String, window:Int, sym:String, syms:Array<String>);
}
