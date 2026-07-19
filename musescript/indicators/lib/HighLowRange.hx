package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * High-Low Range: a stateless per-bar transform reporting the bar's raw
 * trading range.
 *
 * HighLowRange = high - low
 */
class HighLowRange implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		return bar.high - bar.low;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "HighLowRange";

	public static function spec():IndicatorSpec {
		return {
			name: "high_low_range", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "high_low_range", Math.NaN,
				() -> new HighLowRange(), (i, b) -> (cast i : HighLowRange).update(b))
		};
	}
}
