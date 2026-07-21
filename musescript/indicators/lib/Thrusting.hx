package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Thrusting candlestick pattern — ported from wickra-core's `Thrusting`
 * (vendor/wickra/crates/wickra-core/src/indicators/thrusting.rs).
 *
 * A 2-bar bearish continuation, deeper than In-Neck but short of a piercing
 * reversal. A long black candle is followed by a white candle that opens
 * below the black bar's low and closes well into the black body — but still
 * below its midpoint, so the bounce is not yet a reversal.
 *
 *   long body = |close − open| >= 0.5 * (high − low)
 *   bar1 black & long
 *   bar2 white, opens below bar1's low                (open2 < low1)
 *   bar2 closes above the in-neck zone but below the body midpoint
 *        (close1 + 0.1·body1 < close2 < midpoint(open1, close1))
 *
 * Output is −1.0 when the pattern completes and 0.0 otherwise (bearish-only;
 * never emits +1.0). The first bar always returns 0.0.
 */
class Thrusting implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = prev;
		prev = candle;
		if (bar1 == null) return 0.0;
		var range1 = bar1.high - bar1.low;
		if (range1 <= 0.0) return 0.0;
		var body1 = bar1.open - bar1.close;
		var mid1 = (bar1.open + bar1.close) / 2.0;
		if (bar1.close < bar1.open
			&& body1 >= 0.5 * range1
			&& candle.close > candle.open
			&& candle.open < bar1.low
			&& candle.close > bar1.close + 0.1 * body1
			&& candle.close < mid1) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Thrusting";

	public static function spec():IndicatorSpec {
		return {
			name: "thrusting", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "thrusting", Math.NaN,
				() -> new Thrusting(), (i, b) -> (cast i : Thrusting).update(b))
		};
	}
}
