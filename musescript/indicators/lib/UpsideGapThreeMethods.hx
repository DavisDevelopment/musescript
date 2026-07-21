package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Upside Gap Three Methods candlestick pattern — ported from wickra-core's
 * `UpsideGapThreeMethods`
 * (vendor/wickra/crates/wickra-core/src/indicators/upside_gap_three_methods.rs).
 *
 * A 3-bar bullish continuation. Two white candles advance with an upside
 * body gap between them, then a black candle opens inside the second body
 * and closes inside the first body, partially filling the gap without
 * erasing the prior advance.
 *
 *   bar1 white, bar2 white
 *   upside body gap: open2 > close1   (bar2's body sits entirely above bar1's)
 *   bar3 black, opens within bar2's body and closes within bar1's body
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only;
 * never emits −1.0 — its bearish mirror is downside_gap_three_methods). The
 * first two bars always return 0.0.
 */
class UpsideGapThreeMethods implements MuseIndicator<Bar, Float> {
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
		// bar1 and bar2 are both white.
		if (bar1.close <= bar1.open || bar2.close <= bar2.open) return 0.0;
		// Upside body gap: bar2's body sits entirely above bar1's.
		if (bar2.open <= bar1.close) return 0.0;
		// bar3 is black.
		if (candle.close >= candle.open) return 0.0;
		// bar3 opens within bar2's body and closes within bar1's body.
		if (candle.open > bar2.open
			&& candle.open < bar2.close
			&& candle.close > bar1.open
			&& candle.close < bar1.close) {
			return 1.0;
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
	public function name():String return "UpsideGapThreeMethods";

	public static function spec():IndicatorSpec {
		return {
			name: "upside_gap_three_methods", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "upside_gap_three_methods", Math.NaN,
				() -> new UpsideGapThreeMethods(), (i, b) -> (cast i : UpsideGapThreeMethods).update(b))
		};
	}
}
