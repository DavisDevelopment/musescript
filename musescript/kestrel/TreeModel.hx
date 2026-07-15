package musescript.kestrel;

/**
 * Compact decision-tree model for fast distillation and MuseScript lowering.
 *
 * The tree returns both a scalar prediction and a path embedding, matching the
 * existing Python decision_tree experiment while keeping traversal cheap enough
 * for GraalWasm.
 */
typedef TreeModel = {
	var id:String;
	var featureNames:Array<String>;
	var task:TreeTask;
	var root:TreeNode;
	var ?score:Float;
}

enum TreeTask {
	TRegression;
	TClassification;
}

enum TreeNode {
	TLeaf(value:Float, coeffs:Null<Array<Float>>);
	TSplit(feature:Int, threshold:Float, left:TreeNode, right:TreeNode);
}

typedef TreePrediction = {
	var value:Float;
	var path:Array<Int>;
}
