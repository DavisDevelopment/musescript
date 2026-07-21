package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Wick Ratio — ported from wickra-core's `WickRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/wick_ratio.rs).
 *
 * The signed imbalance between the upper and lower shadows as a fraction of
 * the bar's range:
 *
 *   upper_wick = high − max(open, close)
 *   lower_wick = min(open, close) − low
 *   WickRatio  = (upper_wick − lower_wick) / (high − low)
 *
 * The result lives in [−1, +1]: +1 is a bar that is all upper shadow
 * (shooting-star geometry), −1 all lower shadow (hammer geometry), and 0
 * either a symmetric bar or a wickless one. A zero-range bar yields 0.
 * Stateless per-bar transform: every candle produces one value.
 */
class WickRatio implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var range = candle.high - candle.low;
		if (range == 0.0) {
			// A zero-range bar has no shadows to compare.
			return 0.0;
		}
		var bodyTop = Math.max(candle.open, candle.close);
		var bodyBottom = Math.min(candle.open, candle.close);
		var upperWick = candle.high - bodyTop;
		var lowerWick = bodyBottom - candle.low;
		return (upperWick - lowerWick) / range;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "WickRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "wick_ratio", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "wick_ratio", Math.NaN,
				() -> new WickRatio(), (i, b) -> (cast i : WickRatio).update(b))
		};
	}
}
