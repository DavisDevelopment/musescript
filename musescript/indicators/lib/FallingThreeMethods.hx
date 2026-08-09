package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Falling Three Methods candlestick pattern — a 5-bar bearish continuation:
 * a long down bar, three small consolidation bars contained within its
 * range, then a new long down bar that closes below the first bar's close.
 *
 * bar1: red, real body >= `bodyRatio` of the 5-bar window's average range.
 * bar2..bar4: each contained within bar1's high/low (no bar closes outside
 *             bar1's range), small bodies relative to bar1's.
 * bar5: red, closes below bar1's close (the downtrend has resumed and
 *       progressed past the first leg).
 *
 * Output is -1.0 when the pattern completes on the current (5th) bar, 0.0
 * otherwise.
 */
class FallingThreeMethods implements MuseIndicator<Bar, Float> {
	var buf:RingBuffer<Bar>;

	public function new() {
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		buf.push(bar);
		if (buf.length < 5) return 0.0;
		return compute(buf);
	}

	static function compute(w:RingBuffer<Bar>):Float {
		var bar1 = w.oldest(0), bar2 = w.oldest(1), bar3 = w.oldest(2), bar4 = w.oldest(3), bar5 = w.oldest(4);
		if (bar1.close >= bar1.open) return 0.0; // bar1 must be red
		if (bar5.close >= bar5.open) return 0.0; // bar5 must be red

		var body1 = bar1.open - bar1.close;
		if (body1 <= 0.0) return 0.0;

		for (mid in [bar2, bar3, bar4]) {
			var midBody = Math.abs(mid.close - mid.open);
			if (midBody > 0.5 * body1) return 0.0; // must be small relative to bar1
			if (mid.high > bar1.open || mid.low < bar1.close) return 0.0; // must stay within bar1's range
		}

		if (bar5.close < bar1.close) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		buf = new RingBuffer(5);
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return buf.length == 5;
	public function name():String return "FallingThreeMethods";

	public static function spec():IndicatorSpec {
		return {
			name: "falling_three_methods", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "falling_three_methods", Math.NaN,
				() -> new FallingThreeMethods(), (i, b) -> (cast i : FallingThreeMethods).update(b))
		};
	}
}
