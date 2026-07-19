package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Matching Low candlestick pattern — two consecutive red bars closing at
 * (almost) the same price, signalling a support level is being defended.
 *
 * tol = tolerance * average of the two bars' ranges
 *
 * bullish (+1.0): both bars red with a real body, and
 *                 |bar2.close - bar1.close| <= tol.
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class MatchingLow implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;

	public function new(tolerance:Float = 0.05) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	function compute(bar1:Bar, bar2:Bar):Float {
		if (bar1.close >= bar1.open || bar2.close >= bar2.open) return 0.0; // both must be red
		var avgRange = ((bar1.high - bar1.low) + (bar2.high - bar2.low)) / 2.0;
		if (avgRange <= 0.0) return 0.0;
		var tol = tolerance * avgRange;
		if (Math.abs(bar2.close - bar1.close) <= tol) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "MatchingLow";

	public static function spec():IndicatorSpec {
		return {
			name: "matching_low", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "matching_low:" + tol, Math.NaN,
					() -> new MatchingLow(tol), (i, b) -> (cast i : MatchingLow).update(b));
			}
		};
	}
}
