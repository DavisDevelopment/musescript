package musescript.kestrel;

/**
 * Typed Kestrel feature expression.
 *
 * This is intentionally runtime-neutral: the same node can lower to MuseScript
 * source, GraalWasm helpers, or an on-device JSON manifest.
 */
enum FeatureExpr {
	FConst(v:Float);
	FField(name:String);
	FIndicator(name:String, src:FeatureExpr, window:Int);
	FLookback(src:FeatureExpr, n:Int);
	FArith(op:String, a:FeatureExpr, b:FeatureExpr);
	FZScore(src:FeatureExpr, scope:ZScoreScope);
	FModelScore(modelId:String);
	FTreeValue(treeId:String);
	FTreeBit(treeId:String, bit:Int);
	FGraphMetric(queryId:String, metric:String);
}

enum ZScoreScope {
	ZTime(window:Int);
	ZCrossSection;
	ZGlobal;
}
