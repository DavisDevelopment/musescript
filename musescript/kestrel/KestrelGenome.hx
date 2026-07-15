package musescript.kestrel;

import musescript.evo.StrategyGenome;

typedef KestrelGenome = {
	> StrategyGenome,
	var featureBindings:Array<FeatureBinding>;
	var graphQueries:Array<GraphQuerySpec>;
	var treeModels:Array<TreeModel>;
	var ?manifestId:String;
}
