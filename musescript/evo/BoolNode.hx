package musescript.evo;

enum BoolNode {
	BCross(dir:String, a:SeriesNode, b:SeriesNode);
	BCmp(op:String, a:ScalarNode, b:ScalarNode);
	BTrend(dir:String, s:SeriesNode, window:Int);
	BAnd(a:BoolNode, b:BoolNode);
	BOr(a:BoolNode, b:BoolNode);
	BNot(a:BoolNode);
}
