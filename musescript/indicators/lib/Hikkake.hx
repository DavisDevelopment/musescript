package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hikkake ("trap") pattern — a 3-bar setup: an inside bar (bar2 fully
 * contained within bar1's range) followed by a bar3 that breaks out of
 * bar2's range in one direction, trapping breakout traders on the wrong
 * side.
 *
 * bar2 inside bar1:  bar2.high <= bar1.high && bar2.low >= bar1.low
 * bar3 breaks up:     bar3.high > bar2.high  -> -1.0 (bearish trap: false
 *                      upside breakout, expect reversal down)
 * bar3 breaks down:   bar3.low < bar2.low    -> +1.0 (bullish trap: false
 *                      downside breakout, expect reversal up)
 *
 * Output is 0.0 otherwise (including the first two bars, or when bar2
 * isn't actually an inside bar).
 */
class Hikkake implements MuseIndicator<Bar, Float> {
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
		var isInside = bar2.high <= bar1.high && bar2.low >= bar1.low;
		if (!isInside) return 0.0;

		if (bar3.high > bar2.high) return -1.0;
		if (bar3.low < bar2.low) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		prevPrev = null;
		prev = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "Hikkake";

	public static function spec():IndicatorSpec {
		return {
			name: "hikkake", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "hikkake", Math.NaN,
				() -> new Hikkake(), (i, b) -> (cast i : Hikkake).update(b))
		};
	}
}
