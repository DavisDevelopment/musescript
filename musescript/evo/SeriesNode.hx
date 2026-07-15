package musescript.evo;

enum SeriesNode {
	SPrice(field:String);
	SInd(name:String, field:String, window:Int, ?src:SeriesNode);
}
