package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Unique Three River (Bottom) candlestick pattern — ported from wickra-core's
 * `UniqueThreeRiver`
 * (vendor/wickra/crates/wickra-core/src/indicators/unique_three_river.rs).
 *
 * A 3-bar bullish reversal. A long black candle is followed by a smaller
 * black candle whose body sits inside the first but whose long lower shadow
 * probes a new low, then a small white candle that stays below the second
 * body. The fresh low that fails to hold marks an exhausted decline.
 *
 *   bar1 long black: open1 − close1 >= 0.5 * (high1 − low1)
 *   bar2 black, body inside bar1's body, with a new low (low2 < low1)
 *   bar3 small white, contained below bar2's body (high3 <= close2)
 *   small body: close3 − open3 <= 0.3 * (high3 − low3)
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only;
 * never emits −1.0). The first two bars always return 0.0.
 */
class UniqueThreeRiver implements MuseIndicator<Bar, Float> {
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
		// bar1 is a long black body.
		if (bar1.open <= bar1.close) return 0.0;
		var range1 = bar1.high - bar1.low;
		if (bar1.open - bar1.close < 0.5 * range1) return 0.0;
		// bar2 is black, its body inside bar1's body, with a new low.
		if (bar2.open <= bar2.close) return 0.0;
		if (bar2.open > bar1.open || bar2.close < bar1.close) return 0.0;
		if (bar2.low >= bar1.low) return 0.0;
		// bar3 is a small white candle contained below bar2's body.
		if (candle.close <= candle.open) return 0.0;
		var range3 = candle.high - candle.low;
		if (candle.close - candle.open > 0.3 * range3) return 0.0;
		if (candle.high > bar2.close) return 0.0;
		return 1.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "UniqueThreeRiver";

	public static function spec():IndicatorSpec {
		return {
			name: "unique_three_river", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "unique_three_river", Math.NaN,
				() -> new UniqueThreeRiver(), (i, b) -> (cast i : UniqueThreeRiver).update(b))
		};
	}
}
