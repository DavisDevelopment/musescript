package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Takuri candlestick pattern — a single-bar bullish reversal, a stricter
 * Dragonfly Doji. Open, close, and high sit at the very top of the bar with
 * a negligible upper shadow, while an exceptionally long lower shadow shows
 * price was driven sharply down and then bid all the way back.
 *
 * range = high - low
 * doji             = |close - open| <= 0.1 * range
 * negligible upper = high - max(open, close) <= 0.05 * range
 * very long lower  = min(open, close) - low  >= 0.7  * range
 *
 * Output is +1.0 when the Takuri prints and 0.0 otherwise (bullish-only,
 * never emits -1.0). A strict subset of DragonflyDoji.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/takuri.rs
 */
class Takuri implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var range = candle.high - candle.low;
		if (range <= 0.0) return 0.0;
		if (Math.abs(candle.close - candle.open) > 0.1 * range) return 0.0;
		var upper = candle.high - Math.max(candle.open, candle.close);
		var lower = Math.min(candle.open, candle.close) - candle.low;
		if (upper <= 0.05 * range && lower >= 0.7 * range) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Takuri";

	public static function spec():IndicatorSpec {
		return {
			name: "takuri", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "takuri", Math.NaN,
				() -> new Takuri(), (i, b) -> (cast i : Takuri).update(b))
		};
	}
}
