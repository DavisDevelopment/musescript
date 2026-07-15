package musescript.kestrel;

import musescript.kestrel.ModelManifest.ModelHead;

typedef PipelineSpec = {
	var id:String;
	var stages:Array<PipelineStage>;
	var manifest:ModelManifest;
	var search:KestrelSearchSpec;
}

enum PipelineStage {
	SFeatures(bindings:Array<FeatureBinding>);
	SGraph(queries:Array<GraphQuerySpec>);
	SModel(heads:Array<ModelHead>);
	SDistill(sourceModel:String, targetTree:String, maxDepth:Int);
	SEvolve(population:Int, generations:Int);
	SExport(path:String);
}

typedef KestrelSearchSpec = {
	var population:Int;
	var generations:Int;
	var maxNodes:Int;
	var allowGraph:Bool;
	var allowModels:Bool;
	var allowTreeDistill:Bool;
}
