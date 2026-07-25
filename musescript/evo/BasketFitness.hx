package musescript.evo;

/**
 * Aggregates one genome's per-symbol backtest results into a single fitness-comparable triple,
 * for CorpusEvoRun's opt-in `--tapes` multi-symbol basket mode (see PLAN file / this session's
 * multi-symbol plan). Deliberately tiny and dependency-free (no `Bar`/`Fitness` imports) so it
 * compiles under both the JVM `graal` build (CorpusEvoRun's worker pools) and the plain JS test
 * build, letting this get real regression coverage via `node build/js/tests.js` the same as
 * everything else in `musescript.evo`.
 */
class BasketFitness {
	/**
	 * `trades` sums across symbols (total activity across the basket); `sharpe` is the MEAN across
	 * symbols (the standard basket-Sharpe convention -- a documented, not-yet-implemented
	 * follow-up is a `mean - lambda * stdev` consistency penalty, favoring a genome that's OK
	 * everywhere over one that's great on one symbol and terrible on the rest); `finalEquity`
	 * sums. A genome invalid on ANY one symbol (fewer than 1 trade, or a NaN sharpe -- the same
	 * "never really traded" / "blew up" signal `Fitness.score` already treats as NEG_INF-worthy
	 * for a single tape) makes the WHOLE aggregate invalid too, matching the same sentinel shape
	 * (`trades:0, sharpe:NaN, finalEquity:0`) a single-symbol invalid eval already uses --
	 * silently averaging away a blowup on one symbol just because the genome happened to work on
	 * the others would be exactly the kind of exploitable blind spot this session's
	 * `Metrics.returnsFromEquity` bug already showed evolution WILL find and reward.
	 *
	 * A single-element `results` array degenerates to EXACTLY that one result unchanged (sum of
	 * one = itself, mean of one = itself) -- the `basket.length == 1` case CorpusEvoRun's existing
	 * single-`--tape` runs use is byte-identical to calling this function or not at all, for any
	 * VALID result. (An already-invalid single result's `finalEquity` is normalized to `0` here,
	 * same as the shared invalid sentinel -- the one place this differs from a bare passthrough,
	 * and only for a genome that was already going to score NEG_INF regardless.)
	 *
	 * `weights` (default `null` = uniform mean = exactly the behavior above/today's, for every
	 * caller that doesn't opt in) lets CorpusEvoRun's `--curriculum` bias the mean toward symbols
	 * the population is currently worst at, instead of a plain average -- see this session's
	 * neuroevolution-inspired-upgrades plan. Must be the same length as `results`, one weight per
	 * symbol in basket order; NOT required to sum to 1 (normalized internally).
	 */
	public static function aggregateBasket(results:Array<{trades:Int, sharpe:Float, finalEquity:Float}>, ?weights:Array<Float>):{trades:Int, sharpe:Float, finalEquity:Float} {
		var anyInvalid = false;
		var tradesSum = 0;
		var equitySum = 0.0;
		for (r in results) {
			if (r.trades < 1 || Math.isNaN(r.sharpe)) anyInvalid = true;
			tradesSum += r.trades;
			equitySum += r.finalEquity;
		}
		if (anyInvalid) return {trades: 0, sharpe: Math.NaN, finalEquity: 0};
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
		return {trades: tradesSum, sharpe: sharpe, finalEquity: equitySum};
	}
}
