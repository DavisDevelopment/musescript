package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Stalled Pattern (Deliberation) candlestick pattern — a 3-bar bearish
 * reversal warning. Two long white candles push higher, then a small-bodied
 * white candle opens at or near the top of the second body and barely
 * advances — the rally is running out of breath.
 *
 * long body  = |close - open| >= 0.5 * (high - low)
 * small body = |close - open| <= 0.3 * (high - low)
 * bar1, bar2 long white; bar3 small white
 * rising closes: close3 > close2 > close1
 * bar3 rides the shoulder: open3 >= close2 - 0.1 * (high2 - low2)
 *
 * Output is -1.0 when the pattern completes and 0.0 otherwise (bearish-only,
 * never emits +1.0). The first two bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/stalled_pattern.rs
 */
class StalledPattern implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = c1;
		var bar2 = c2;
		c1 = c2;
		c2 = candle;
		if (bar1 == null || bar2 == null) return 0.0;
		var range1 = bar1.high - bar1.low;
		var range2 = bar2.high - bar2.low;
		var range3 = candle.high - candle.low;
		if (range1 <= 0.0 || range2 <= 0.0 || range3 <= 0.0) return 0.0;
		// All three candles are white.
		if (bar1.close <= bar1.open || bar2.close <= bar2.open || candle.close <= candle.open) return 0.0;
		// Rising closes.
		if (candle.close <= bar2.close || bar2.close <= bar1.close) return 0.0;
		// bar1 and bar2 are long bodies.
		if (bar1.close - bar1.open < 0.5 * range1 || bar2.close - bar2.open < 0.5 * range2) return 0.0;
		// bar3 is a small body.
		if (candle.close - candle.open > 0.3 * range3) return 0.0;
		// bar3 opens at or near the top of bar2's body (rides the shoulder).
		if (candle.open >= bar2.close - 0.1 * range2) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "StalledPattern";

	public static function spec():IndicatorSpec {
		return {
			name: "stalled_pattern", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "stalled_pattern", Math.NaN,
				() -> new StalledPattern(), (i, b) -> (cast i : StalledPattern).update(b))
		};
	}
}
