package musescript.evo;

/**
 * Aggregates one genome's per-symbol backtest results into a single fitness-comparable record,
 * for CorpusEvoRun's `--tapes` multi-symbol basket mode.
 *
 * Invalid on ANY symbol (trades &lt; 1, NaN sharpe, or bankrupt) → whole aggregate invalid
 * (`trades:0, sharpe:NaN`), matching `Fitness.scoreFacts` NEG_INF contract.
 */
class BasketFitness {
	/**
	 * `trades` / `finalEquity` sum; `sharpe` is the (optionally weighted) mean across symbols.
	 * Optional `bankrupt` on each result ORs into the aggregate; any bankrupt forces invalid.
	 */
	public static function aggregateBasket(
		results:Array<{trades:Int, sharpe:Float, finalEquity:Float, ?bankrupt:Bool}>,
		?weights:Array<Float>
	):{trades:Int, sharpe:Float, finalEquity:Float, bankrupt:Bool} {
		var anyInvalid = false;
		var anyBankrupt = false;
		var tradesSum = 0;
		var equitySum = 0.0;
		for (r in results) {
			if (r.bankrupt == true) { anyBankrupt = true; anyInvalid = true; }
			if (r.trades < 1 || Math.isNaN(r.sharpe)) anyInvalid = true;
			tradesSum += r.trades;
			equitySum += r.finalEquity;
		}
		if (anyInvalid) return {trades: 0, sharpe: Math.NaN, finalEquity: 0, bankrupt: anyBankrupt};
		var sharpe:Float;
		if (weights == null) {
			var sharpeSum = 0.0;
			for (r in results) sharpeSum += r.sharpe;
			sharpe = sharpeSum / results.length;
		} else {
			var weightSum = 0.0;
			for (w in weights) weightSum += w;
			var weighted = 0.0;
			for (i in 0...results.length) weighted += results[i].sharpe * weights[i];
			sharpe = weightSum > 0 ? weighted / weightSum : weighted / results.length;
		}
		return {trades: tradesSum, sharpe: sharpe, finalEquity: equitySum, bankrupt: false};
	}

	/** Canonical oracle score for an aggregate (no parsimony). Uses `Fitness.defaultMinTrades` when omitted. */
	public static inline function scoreAggregate(agg:{trades:Int, sharpe:Float, ?bankrupt:Bool}, ?minTrades:Null<Int>):Float {
		return Fitness.scoreFacts(agg.trades, agg.sharpe, agg.bankrupt == true, minTrades);
	}
}
