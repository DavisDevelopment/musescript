package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Upside Gap Two Crows candlestick pattern — ported from wickra-core's
 * `UpsideGapTwoCrows`
 * (vendor/wickra/crates/wickra-core/src/indicators/upside_gap_two_crows.rs).
 *
 * A 3-bar bearish reversal that appears after an advance. Two black candles
 * gap up above a long white candle; the second black candle engulfs the
 * first crow yet still closes above the white body, leaving the upside gap
 * open.
 *
 *   bar1 green (long white)
 *   bar2 red   & its body gaps up above bar1's body  (bar2.close > bar1.close)
 *   bar3 red   & opens above bar2's open             (bar3.open  > bar2.open)
 *              & closes below bar2's close           (bar3.close < bar2.close)
 *              & closes above bar1's close           (bar3.close > bar1.close)
 *
 * Output is −1.0 when the pattern completes and 0.0 otherwise (bearish-only;
 * never emits +1.0). The first two bars always return 0.0.
 */
class UpsideGapTwoCrows implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = prevPrev;
		var bar2 = prev;
		prevPrev = prev;
		prev = candle;
		if (bar1 == null || bar2 == null) return 0.0;
		if (bar1.close > bar1.open
			&& bar2.close < bar2.open
			&& bar2.close > bar1.close
			&& candle.close < candle.open
			&& candle.open > bar2.open
			&& candle.close < bar2.close
			&& candle.close > bar1.close) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "UpsideGapTwoCrows";

	public static function spec():IndicatorSpec {
		return {
			name: "upside_gap_two_crows", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "upside_gap_two_crows", Math.NaN,
				() -> new UpsideGapTwoCrows(), (i, b) -> (cast i : UpsideGapTwoCrows).update(b))
		};
	}
}
