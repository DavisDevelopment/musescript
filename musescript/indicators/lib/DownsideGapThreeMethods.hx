package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Downside Gap Three Methods candlestick pattern — a 3-bar bearish
 * continuation: two red bars with a true gap between them, then a green bar
 * that opens inside the second body and closes back inside the gap
 * (partially "filling" it without erasing the downtrend).
 *
 * bar1: red with a real body.
 * bar2: red, gaps down from bar1 (bar2.high < bar1.low).
 * bar3: green, opens within bar2's body, closes within the gap —
 *       specifically bar2.high < bar3.close < bar1.low.
 *
 * Output is -1.0 when the pattern completes on the current (3rd) bar, 0.0
 * otherwise.
 */
class DownsideGapThreeMethods implements MuseIndicator<Bar, Float> {
	var prevPrev:Null<Bar>;
	var prev:Null<Bar>;

	public function new() {
		prevPrev = null;
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp == null || p == null) return pp == null && p == null ? null : 0.0;
		return compute(pp, p, bar);
	}

	static function compute(bar1:Bar, bar2:Bar, bar3:Bar):Float {
		if (bar1.close >= bar1.open) return 0.0; // bar1 must be red
		if (bar2.close >= bar2.open) return 0.0; // bar2 must be red
		if (bar2.high >= bar1.low) return 0.0; // bar2 must gap down from bar1

		if (bar3.close <= bar3.open) return 0.0; // bar3 must be green
		var bar2BodyTop = Math.max(bar2.open, bar2.close);
		var bar2BodyBottom = Math.min(bar2.open, bar2.close);
		if (bar3.open < bar2BodyBottom || bar3.open > bar2BodyTop) return 0.0; // opens within bar2's body

		if (bar3.close > bar2.high && bar3.close < bar1.low) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prevPrev = null;
		prev = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "DownsideGapThreeMethods";

	public static function spec():IndicatorSpec {
		return {
			name: "downside_gap_three_methods", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "downside_gap_three_methods", Math.NaN,
				() -> new DownsideGapThreeMethods(), (i, b) -> (cast i : DownsideGapThreeMethods).update(b))
		};
	}
}
