package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Stick Sandwich candlestick pattern — a 3-bar bullish reversal. A black
 * candle is followed by a white candle that trades entirely above the first
 * close, then a second black candle drives price back down to close at the
 * same level as the first. The matching closes "sandwich" the white candle
 * and mark a support floor.
 *
 * bar1 black, bar2 white, bar3 black
 * bar2 trades above bar1's close: low2 > close1
 * matching closes: |close3 - close1| <= 0.1 * (high1 - low1)
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only,
 * never emits -1.0). The first two bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/stick_sandwich.rs
 */
class StickSandwich implements MuseIndicator<Bar, Float> {
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
		// bar1 black, bar2 white, bar3 black.
		if (bar1.close >= bar1.open || bar2.close <= bar2.open || candle.close >= candle.open) return 0.0;
		// The white candle trades entirely above the first close.
		if (bar2.low <= bar1.close) return 0.0;
		// The two black candles close at the same level (the sandwich).
		var range1 = bar1.high - bar1.low;
		if (Math.abs(candle.close - bar1.close) <= 0.1 * range1) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "StickSandwich";

	public static function spec():IndicatorSpec {
		return {
			name: "stick_sandwich", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "stick_sandwich", Math.NaN,
				() -> new StickSandwich(), (i, b) -> (cast i : StickSandwich).update(b))
		};
	}
}
