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
	 * OrderSim.hx's doc comment) -- false for every existing caller that doesn't pass one.
	 * `Fitness.score` / `Fitness.scoreFacts` / `Fitness.robustScore` clamp bankrupt runs to NEG_INF. */
	public var bankrupt:Bool = false;
	/** Optional — set by Fitness.evaluate from `harness.orders.equity` (a per-bar mark-to-market
	 * curve the backtest already tracks internally for free). `Fitness.robustScore` collapses it
	 * into one scalar; `Fitness.windowSharpes` exposes the per-window vector for `--lexicase`
	 * case fitness on single-tape runs. Every existing caller that only ever reads `.sharpe` is
	 * completely unaffected. */
	public var equity:Null<Array<Float>>;
	/** Leakage-free forecast skill of the genome's REFERENCED projections (see `ProjectionScore`);
	 * `NaN` when the genome has none. `projScores` is the per-projection breakdown. Opt-in — only
	 * populated by a caller that asks for it (e.g. the MAP-Elites descriptor pass), never computed on
	 * the plain fitness hot path, so every existing caller is unaffected. */
	public var projScore:Float = Math.NaN;
	public var projScores:Null<Array<Float>> = null;

	public function new(ok:Bool, sharpe:Float, trades:Int, finalEquity:Float, backend:String, ?error:String) {
		this.ok = ok;
		this.sharpe = sharpe;
		this.trades = trades;
		this.finalEquity = finalEquity;
		this.backend = backend;
		this.error = error;
	}
}
