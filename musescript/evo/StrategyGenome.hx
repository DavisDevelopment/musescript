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
	 * Lazy `Canonical.structuralKey` / `nodeCount` memo. Valid only while the five roots + params
	 * are unchanged. `Variation.copyGenome` deliberately omits these so any splice starts cold;
	 * elites reused across generations keep their hits. Not part of the genome's identity.
	 */
	var ?keyCache:String;
	var ?nodeCountCache:Int;
}
