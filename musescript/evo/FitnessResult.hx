package musescript.evo;

class FitnessResult {
	public var ok:Bool;
	public var sharpe:Float;
	public var trades:Int;
	public var finalEquity:Float;
	public var backend:String;
	public var error:Null<String>;
	/** Optional — set by Fitness.evaluate from the backtest's fills (see BacktestResult.hx and
	 * MapElites.hx). A plain settable field rather than a constructor param so the one existing
	 * call site (Fitness.evaluate) doesn't need every future positional-arg change to touch it. */
	public var fills:Null<Array<musescript.harness.Fill>>;

	public function new(ok:Bool, sharpe:Float, trades:Int, finalEquity:Float, backend:String, ?error:String) {
		this.ok = ok;
		this.sharpe = sharpe;
		this.trades = trades;
		this.finalEquity = finalEquity;
		this.backend = backend;
		this.error = error;
	}
}
