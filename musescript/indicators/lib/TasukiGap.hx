package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tasuki Gap candlestick pattern — a 3-bar continuation. Two same-coloured
 * candles open a body gap in the trend direction, then an opposite-coloured
 * candle opens inside the second body and closes back *into* the gap without
 * filling it — the gap holds, so the trend is expected to continue.
 *
 * Upside (bullish, +1):
 *   bar1 white, bar2 white with an upside body gap (open2 > close1)
 *   bar3 black, opens within bar2's body, closes inside the gap
 *   (close1 < close3 < open2)
 * Downside (bearish, -1): the mirror image with black candles and a
 * downside gap.
 *
 * Output is 0.0 otherwise; the first two bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/tasuki_gap.rs
 */
class TasukiGap implements MuseIndicator<Bar, Float> {
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

		var up = bar1.close > bar1.open && bar2.close > bar2.open;
		var down = bar1.close < bar1.open && bar2.close < bar2.open;
		if (up) {
			if (bar2.open <= bar1.close) return 0.0; // no upside body gap
			if (candle.close >= candle.open) return 0.0; // bar3 must be black
			if (candle.open <= bar2.open || candle.open >= bar2.close) return 0.0; // bar3 must open within bar2's body
			if (candle.close < bar2.open && candle.close > bar1.close) return 1.0; // bar3 closes inside the gap
			return 0.0;
		}
		if (down) {
			if (bar2.open >= bar1.close) return 0.0; // no downside body gap
			if (candle.close <= candle.open) return 0.0; // bar3 must be white
			if (candle.open >= bar2.open || candle.open <= bar2.close) return 0.0; // bar3 must open within bar2's body
			if (candle.close > bar2.open && candle.close < bar1.close) return -1.0; // bar3 closes inside the gap
			return 0.0;
		}
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "TasukiGap";

	public static function spec():IndicatorSpec {
		return {
			name: "tasuki_gap", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "tasuki_gap", Math.NaN,
				() -> new TasukiGap(), (i, b) -> (cast i : TasukiGap).update(b))
		};
	}
}
