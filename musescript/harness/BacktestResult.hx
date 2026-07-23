package musescript.harness;

typedef BacktestResult = {
	var equity:Array<Float>;
	var returns:Array<Float>;
	var trades:Int;
	var sharpe:Float;
	var maxDrawdown:Float;
	var winRate:Float;
	var finalEquity:Float;
	/** Optional — every OrderSim already collects this for free (IDE trade log), so exposing it
	 * costs nothing at existing construction sites (structural typedef, optional field, no
	 * existing struct literal needs to change). Lets a caller (e.g. musescript.evo's MAP-Elites
	 * behavioral archive) derive a real behavioral descriptor -- trade frequency, avg holding
	 * period, long/short bias -- from the SAME fills every backend already produces identically,
	 * instead of adding yet another parallel bookkeeping path that could drift from OrderSim's. */
	var ?fills:Array<Fill>;
}
