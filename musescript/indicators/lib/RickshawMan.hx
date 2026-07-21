package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rickshaw Man candlestick pattern — a single-bar indecision signal. A
 * long-legged doji whose tiny body sits near the *middle* of a wide range.
 *
 * range = high - low
 * doji         = |close - open| <= 0.1 * range
 * long upper   = high - max(open, close) >= 0.3 * range
 * long lower   = min(open, close) - low  >= 0.3 * range
 * centred body = body midpoint within the central 40-60 % of the range
 *
 * Output is +1.0 when the rickshaw man prints and 0.0 otherwise — a
 * non-directional indecision flag that never emits -1.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/rickshaw_man.rs
 */
class RickshawMan implements MuseIndicator<Bar, Float> {
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
		var bodyMid = 0.5 * (candle.open + candle.close);
		var pos = (bodyMid - candle.low) / range;
		if (upper >= 0.3 * range && lower >= 0.3 * range && pos >= 0.4 && pos <= 0.6) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "RickshawMan";

	public static function spec():IndicatorSpec {
		return {
			name: "rickshaw_man", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "rickshaw_man", Math.NaN,
				() -> new RickshawMan(), (i, b) -> (cast i : RickshawMan).update(b))
		};
	}
}
