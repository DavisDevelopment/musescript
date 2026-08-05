package musescript.evo;

typedef StrategyGenome = {
	var entryLong:BoolNode;
	var entryShort:BoolNode;
	var exitLong:BoolNode;
	var exitShort:BoolNode;
	var size:ScalarNode;
	var params:Array<EvoParam>;
	var name:String;
	var ?lineage:Array<String>;
	var ?seedOrigin:Null<Int>;
	/**
	 * Named forward projections (Monte-Carlo fans) this genome computes each bar and the policy may
	 * read (PROJECTION_COEVOLUTION_PLAN.md). Null/absent ⇒ byte-identical to a projection-free genome:
	 * neither `Expand` nor `Canonical` reads this until a policy node references a projection, so an
	 * unreferenced projection changes neither rendering nor the fitness key. This IS part of genome
	 * identity (unlike the cache fields below) — `Variation.copyGenome` preserves it so splices and
	 * elites keep their projections.
	 */
	var ?projections:Array<ProjectionDecl>;
	/**
	 * Panel portfolio-action template (panel genomes v1+). Null/absent ⇒ Expand emits the classic
	 * single-name `long`/`short`/`flat` skeleton. When set, Expand emits HostABI `buy` /
	 * `sell_all` / `target_weight` / `rebalance_equal` with literal symbols, or closed
	 * rank→bag `portfolio_apply(bag_*)` under PD. Genome identity —
	 * preserved by `Variation.copyGenome` / compact / simplify like `projections`.
	 */
	var ?panelAction:PanelAction;
	/**
	 * Lazy `Canonical.structuralKey` / `nodeCount` / `shapeVector` memos. Valid only while the five
	 * roots + params are unchanged. `Variation.copyGenome` deliberately omits these so any splice
	 * starts cold; elites reused across generations keep their hits. Not part of the genome's identity.
	 */
	var ?keyCache:String;
	var ?nodeCountCache:Int;
	var ?shapeVectorCache:haxe.ds.Vector<Int>;
	/**
	 * Per-instance Variation catalogs for the current `Variation.cacheGen`. Tournament re-picks the
	 * same elite *objects* hundreds of times per step; hitting these skips `memoLock` + map lookup
	 * (measured: lock traffic was a large slice of imperfect `step.xo` parallel efficiency).
	 * Invalidated by gen stamp, not by clearing — `copyGenome` omits them so splices stay cold.
	 */
	var ?variationCacheGen:Int;
	var ?catalogCache:Array<CatalogEntry>;
	var ?boolCatalogCache:Array<CatalogEntry>;
	var ?boolSiteKeysCache:IntPairList;
	var ?donorPoolCache:Array<Dynamic>;
}
