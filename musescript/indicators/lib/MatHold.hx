package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Mat Hold candlestick pattern — a 5-bar bullish continuation, the mirror
 * image of `FallingThreeMethods`: a long up bar, three small consolidation
 * bars contained within its range, then a new long up bar that closes above
 * the first bar's high.
 *
 * bar1: green, real body >= half the 5-bar window's bar1 body.
 * bar2..bar4: small bodies relative to bar1's, each contained within
 *             bar1's high/low.
 * bar5: green, closes above bar1's high (the uptrend has resumed and
 *       progressed past the first leg).
 *
 * Output is +1.0 when the pattern completes on the current (5th) bar, 0.0
 * otherwise.
 */
class MatHold implements MuseIndicator<Bar, Float> {
	var buf:Array<Bar>;

	public function new() {
		buf = [];
	}

	public function update(bar:Bar):Null<Float> {
		buf.push(bar);
		if (buf.length > 5) buf.shift();
		if (buf.length < 5) return 0.0;
		return compute(buf);
	}

	static function compute(w:Array<Bar>):Float {
		var bar1 = w[0], bar2 = w[1], bar3 = w[2], bar4 = w[3], bar5 = w[4];
		if (bar1.close <= bar1.open) return 0.0; // bar1 must be green
		if (bar5.close <= bar5.open) return 0.0; // bar5 must be green

		var body1 = bar1.close - bar1.open;
		if (body1 <= 0.0) return 0.0;

		for (mid in [bar2, bar3, bar4]) {
			var midBody = Math.abs(mid.close - mid.open);
			if (midBody > 0.5 * body1) return 0.0;
			if (mid.high > bar1.high || mid.low < bar1.open) return 0.0;
		}

		if (bar5.close > bar1.high) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		buf = [];
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return buf.length == 5;
	public function name():String return "MatHold";

	public static function spec():IndicatorSpec {
		return {
			name: "mat_hold", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "mat_hold", Math.NaN,
				() -> new MatHold(), (i, b) -> (cast i : MatHold).update(b))
		};
	}
}
