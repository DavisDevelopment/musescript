package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Homing Pigeon candlestick pattern — a 2-bar bullish reversal: two
 * consecutive red bars where the second's smaller body is fully contained
 * inside the first's (a same-color variant of `Harami`, signalling the
 * selling pressure is fading rather than reversing outright).
 *
 * bar1: red with a real body.
 * bar2: also red, and bar2's body lies entirely within bar1's body
 *       (bar2.open <= bar1.open && bar2.close >= bar1.close).
 *
 * Output is 1.0 when the pattern completes, 0.0 otherwise (including the
 * first bar).
 */
class HomingPigeon implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	static function compute(bar1:Bar, bar2:Bar):Float {
		var bar1Red = bar1.close < bar1.open;
		var bar2Red = bar2.close < bar2.open;
		if (!bar1Red || !bar2Red) return 0.0;
		if (bar2.open <= bar1.open && bar2.close >= bar1.close) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "HomingPigeon";

	public static function spec():IndicatorSpec {
		return {
			name: "homing_pigeon", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "homing_pigeon", Math.NaN,
				() -> new HomingPigeon(), (i, b) -> (cast i : HomingPigeon).update(b))
		};
	}
}
