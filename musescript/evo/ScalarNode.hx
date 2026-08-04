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
	 * `b` is required for `dot` (ignored for mean/sum). WASM may claim native on the
	 * scalar subset; NMA is `nma-unsupported` → Expand→interp/WASM (honest fallback).
	 */
	KNp(op:String, a:SeriesNode, window:Int, ?b:SeriesNode);
	/**
	 * Closed gated PD palette leaf (`Palette.PD_OPS`). Grown only when
	 * `Variation.configureForPd` is open **and** a fixed universe is set — no
	 * open groupby/merge/HTTP. Expand emits literal-safe one-row
	 * `pd_from_columns` + percentile `pd_xs_rank` cell extract, and coerces
	 * onto `PanelAction` / `target_weight` for panel fitness. WASM/NMA: all-U /
	 * `nma-unsupported` → Expand→interp/JS only.
	 */
	KPd(op:String, kind:String, window:Int, sym:String, syms:Array<String>);
}
