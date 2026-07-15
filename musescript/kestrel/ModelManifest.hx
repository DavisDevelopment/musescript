package musescript.kestrel;

/**
 * JSON-safe Kestrel model manifest.
 *
 * Mirrors the Python export_kestrel.py contract where possible, while allowing
 * Haxe-authored model heads and tree distillations to travel with a strategy.
 */
typedef ModelManifest = {
	var id:String;
	var format:String;
	var channels:Array<String>;
	var features:Array<FeatureBinding>;
	var heads:Array<ModelHead>;
	var trees:Array<TreeModel>;
	var graphQueries:Array<GraphQuerySpec>;
	var ?metadata:Dynamic;
}

enum ModelHead {
	HZero(id:String, latentDim:Int);
	HLinear(id:String, weights:Array<Float>, bias:Float);
	HMlp(id:String, w1:Array<Array<Float>>, b1:Array<Float>, w2:Array<Float>, b2:Float);
	HGbdt(id:String, baseline:Float, trees:Array<GbdtTree>);
	HBagged(id:String, heads:Array<ModelHead>);
}

typedef GbdtTree = {
	var isLeaf:Array<Int>;
	var value:Array<Float>;
	var feature:Array<Int>;
	var threshold:Array<Float>;
	var left:Array<Int>;
	var right:Array<Int>;
	var missingLeft:Array<Int>;
}
