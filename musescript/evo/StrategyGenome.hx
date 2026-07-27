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
