package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.Beta.BetaPair;
import musescript.types.MuseType;

/**
 * Beta-neutral spread: the asset's return with its rolling-beta exposure to
 * the benchmark hedged out.
 *
 * Spread = asset_return - Beta(period) * benchmark_return
 *
 * Beta is estimated over the same trailing window (see `Beta`) and applied
 * to the current bar's pair, so the spread is what remains of the asset's
 * move once its systematic co-movement with the benchmark is removed —
 * useful as the residual leg of a pairs/hedge strategy.
 */
class BetaNeutralSpread implements MuseIndicator<BetaPair, Float> {
	var beta:Beta;

	public function new(period:Int) {
		beta = new Beta(period);
	}

	public function update(input:BetaPair):Null<Float> {
		var b = beta.update(input);
		if (b == null) return null;
		return input.a - b * input.b;
	}

	public function reset():Void {
		beta.reset();
	}

	public function warmupPeriod():Int return beta.warmupPeriod();
	public function isReady():Bool return beta.isReady();
	public function name():String return "BetaNeutralSpread";

	public static function spec():IndicatorSpec {
		return {
			name: "beta_neutral_spread", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "beta_neutral_spread:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new BetaNeutralSpread(p), (i, a, b) -> (cast i : BetaNeutralSpread).update({ a: a, b: b }));
			}
		};
	}
}
