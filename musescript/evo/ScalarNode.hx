package musescript.evo;

enum ScalarNode {
	KConst(v:Float);
	KParam(idx:Int);
	KArith(op:String, a:ScalarNode, b:ScalarNode);
	KSeries(s:SeriesNode);
	KLookback(s:SeriesNode, n:Int);
	KFeature(name:String);
}
