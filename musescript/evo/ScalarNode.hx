package musescript.evo;

enum ScalarNode {
	KConst(v:Float);
	KParam(idx:Int);
	KArith(op:String, a:ScalarNode, b:ScalarNode);
	KSeries(s:SeriesNode);
	KLookback(s:SeriesNode, n:Int);
	KFeature(name:String);
	/** Scalar counterpart of `BoolNode.BHole` -- see its doc comment. Optional domain/name for author holes. */
	KHole(inner:ScalarNode, ?domain:HoleDomain, ?name:Null<String>);
}
