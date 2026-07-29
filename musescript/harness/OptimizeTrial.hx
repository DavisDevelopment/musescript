package musescript.harness;

/** One optimize grid/coordinate trial — params applied + backtest result + metric score. */
typedef OptimizeTrial = {
	var params:Map<String, Dynamic>;
	var result:BacktestResult;
	var score:Float;
}
