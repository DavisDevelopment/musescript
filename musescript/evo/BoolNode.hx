package musescript.evo;

enum BoolNode {
	BCross(dir:String, a:SeriesNode, b:SeriesNode);
	BCmp(op:String, a:ScalarNode, b:ScalarNode);
	BTrend(dir:String, s:SeriesNode, window:Int);
	BAnd(a:BoolNode, b:BoolNode);
	BOr(a:BoolNode, b:BoolNode);
	BNot(a:BoolNode);
	/**
	 * Template-evolution marker (see CorpusSeed's `evolve(...)` recognition and Variation's
	 * `buildCatalog`) -- wraps a subtree that is explicitly ELIGIBLE for mutation/crossover in an
	 * otherwise-frozen template genome. Purely a boundary marker: transparent to execution
	 * (Expand.bool unwraps it to `inner`'s own rendering, byte-identical output either way) and to
	 * fitness caching (Canonical.keyBool/countBool unwrap it too, so a hole-wrapped and bare
	 * version of the same logical subtree share one cache entry and one parsimony cost). A genome
	 * with zero BHole/KHole anywhere is untouched by any of this -- see Variation.isTemplated.
	 */
	BHole(inner:BoolNode);

	/**
	 * Opaque boolean leaf: verbatim MuseScript boolean source text that no structured BoolNode
	 * shape can represent (e.g. `rising(macd("close",8,21,5).hist, 3)` -- a multi-output field fed
	 * to a trend builtin -- or the 3-arg `falling(x, n, minBars)` form). The boolean sibling of the
	 * scalar `KFeature` leaf: `Expand.bool` emits `src` verbatim into the boolean when-condition it
	 * already sits in (proven runnable -- the strategy parser accepts these; only CorpusSeed's
	 * reverse-translator ever refused them), and every other pass treats it as an atomic, childless
	 * leaf (Canonical keys/counts the string, Variation never descends into it, TreeSurgery finds no
	 * holes inside). Faithful-not-mutable: the seeded logic runs exactly, evolution varies the
	 * scaffolding AROUND it. Columnar NMA can't evaluate arbitrary source, so a genome containing a
	 * BFeature is `nma-unsupported` and routes to the Expand→interp/VM fallback (Fitness dispatch),
	 * exactly like the scalar KFeature and SProj leaves already do. CorpusSeed only ever MINTS these
	 * as a fail-open fallback for otherwise-unrecognized sub-expressions -- see its `opaqueBool`.
	 */
	BFeature(src:String);
}
