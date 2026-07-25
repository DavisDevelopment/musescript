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
}
