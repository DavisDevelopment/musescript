package musescript.harness;

typedef BacktestResult = {
	var equity:Array<Float>;
	var returns:Array<Float>;
	var trades:Int;
	var sharpe:Float;
	var maxDrawdown:Float;
	var winRate:Float;
	var finalEquity:Float;
}
