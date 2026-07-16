package musescript.kestrel;

/**
 * Portable graph-query spec for strategies that depend on knowledge graph state.
 *
 * This is a compiler/planning description, not a promise of live external knowledge
 * graph execution. `GraphBuiltins.querySpecOptions` adapts its seed and bounds to
 * the dependency-free in-memory runtime without introducing a second query grammar.
 */
typedef GraphQuerySpec = {
	var id:String;
	var seed:GraphSeed;
	var ?relations:Array<String>;
	var ?depth:Int;
	var ?topK:Int;
	var ?maxNodes:Int;
	var ?asOf:String;
	var metrics:Array<GraphMetricSpec>;
}

enum GraphSeed {
	GSymbol(symbol:String);
	GEntity(name:String);
	GQuestion(text:String);
	GFeature(name:String);
}

typedef GraphMetricSpec = {
	var name:String;
	var op:GraphMetricOp;
}

enum GraphMetricOp {
	GNodeCount;
	GEdgeCount;
	GWeightedDegree(relation:Null<String>);
	GRelationExists(relation:String, target:Null<String>);
	GSeedScore;
	GPageRankApprox(iterations:Int);
}
