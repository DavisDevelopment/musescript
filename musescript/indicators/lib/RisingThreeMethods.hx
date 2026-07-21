package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rising Three Methods candlestick pattern — a 5-bar bullish continuation. A
 * long white candle is followed by three small bars that drift back but stay
 * inside its range, then a second long white candle closes above the first.
 *
 * long body = |close - open| >= 0.5 * (high - low)
 * bar1 white & long
 * bar2, bar3, bar4 small bodies, each contained within bar1's high/low range
 * bar5 white, closing above bar1's close
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only,
 * never emits -1.0). The first four bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/rising_three_methods.rs
 */
class RisingThreeMethods implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var c3:Null<Bar>;
	var c4:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = c1;
		var bar2 = c2;
		var bar3 = c3;
		var bar4 = c4;
		c1 = c2;
		c2 = c3;
		c3 = c4;
		c4 = candle;
		if (bar1 == null || bar2 == null || bar3 == null || bar4 == null) return 0.0;
		var range1 = bar1.high - bar1.low;
		if (range1 <= 0.0) return 0.0;
		var body1 = bar1.close - bar1.open;
		if (body1 < 0.5 * range1) return 0.0; // bar1 must be a long white body
		// The three middle bars stay within bar1's range with smaller bodies.
		for (mid in [bar2, bar3, bar4]) {
			if (Math.abs(mid.close - mid.open) >= body1 || mid.high > bar1.high || mid.low < bar1.low) return 0.0;
		}
		// bar5 is a white candle closing above bar1's close.
		if (candle.close > candle.open && candle.close > bar1.close) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "RisingThreeMethods";

	public static function spec():IndicatorSpec {
		return {
			name: "rising_three_methods", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "rising_three_methods", Math.NaN,
				() -> new RisingThreeMethods(), (i, b) -> (cast i : RisingThreeMethods).update(b))
		};
	}
}
