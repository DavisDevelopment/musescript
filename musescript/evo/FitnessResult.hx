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
	/** Set by Fitness.evaluate from `OrderSim.bankrupt` when a caller opts into `equityFloor` (see
	 * OrderSim.hx's doc comment) -- false for every existing caller that doesn't pass one. A
	 * fitness-scoring caller (see CorpusEvoRun's `scoreOf`) that cares about the bankruptcy
	 * difficulty crank checks this and clamps to Fitness.NEG_INF, same as an invalid/zero-trade run. */
	public var bankrupt:Bool = false;
	/** Optional — set by Fitness.evaluate from `harness.orders.equity` (a per-bar mark-to-market
	 * curve the backtest already tracks internally for free). Only `Fitness.robustScore` reads
	 * this -- it splits the curve into windows to compute a robustness-adjusted score instead of
	 * one whole-tape Sharpe (see that function's doc comment). Every existing caller that only
	 * ever reads `.sharpe` is completely unaffected. */
	public var equity:Null<Array<Float>>;

	public function new(ok:Bool, sharpe:Float, trades:Int, finalEquity:Float, backend:String, ?error:String) {
		this.ok = ok;
		this.sharpe = sharpe;
		this.trades = trades;
		this.finalEquity = finalEquity;
		this.backend = backend;
		this.error = error;
	}
}
