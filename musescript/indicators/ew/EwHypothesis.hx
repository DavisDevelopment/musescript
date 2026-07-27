package musescript.indicators.ew;

/** One ranked Elliott hypothesis over a pivot window. */
typedef EwHypothesis = {
	var rank:Int;
	var score:Float;
	var label:String;
	var startBar:Int;
	var endBar:Int;
	var waveCount:Int;
	var degree:Int;
	var offset:Int;
}
