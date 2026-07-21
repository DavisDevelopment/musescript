package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tristar — ported from wickra-core's `Tristar`
 * (vendor/wickra/crates/wickra-core/src/indicators/tristar.rs).
 *
 * A three-doji reversal pattern: three consecutive Doji candles where the
 * middle one gaps away from its neighbours, forming a star.
 *
 *   bullish (+1.0): three dojis, the middle doji's body centre below both
 *                   neighbours' body centres.
 *   bearish (−1.0): three dojis, the middle above both neighbours.
 *   otherwise 0.0.
 *
 * A doji is a candle whose body is <= 0.1 * range (a zero-range bar is not a
 * doji). The three-bar lookback means the first signal lands on the third
 * candle; the first two bars return 0.0.
 */
class Tristar implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var lastValue:Null<Float>;

	public function new() {
		c1 = null;
		c2 = null;
		lastValue = null;
	}

	/** Latest emitted signal if available. */
	public function value():Null<Float> return lastValue;

	static function bodyMid(candle:Bar):Float {
		return (candle.open + candle.close) / 2.0;
	}

	static function isDoji(candle:Bar):Bool {
		var body = Math.abs(candle.close - candle.open);
		var range = candle.high - candle.low;
		return range > 0.0 && body <= 0.1 * range;
	}

	public function update(candle:Bar):Null<Float> {
		if (c1 == null || c2 == null) {
			c1 = c2;
			c2 = candle;
			lastValue = 0.0;
			return 0.0;
		}
		var first = c1;
		var middle = c2;
		var v = if (isDoji(first) && isDoji(middle) && isDoji(candle)) {
			var mid = bodyMid(middle);
			var n1 = bodyMid(first);
			var n3 = bodyMid(candle);
			if (mid > n1 && mid > n3) -1.0;
			else if (mid < n1 && mid < n3) 1.0;
			else 0.0;
		} else {
			0.0;
		};
		c1 = c2;
		c2 = candle;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return lastValue != null;
	public function name():String return "Tristar";

	public static function spec():IndicatorSpec {
		return {
			name: "tristar", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "tristar", Math.NaN,
				() -> new Tristar(), (i, b) -> (cast i : Tristar).update(b))
		};
	}
}
