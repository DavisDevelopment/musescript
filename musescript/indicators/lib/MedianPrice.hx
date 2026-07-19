package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Median Price: a stateless per-bar transform reporting the midpoint of the
 * bar's high/low range.
 *
 * MedianPrice = (high + low) / 2
 */
class MedianPrice implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		return (bar.high + bar.low) / 2.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "MedianPrice";

	public static function spec():IndicatorSpec {
		return {
			name: "median_price", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "median_price", Math.NaN,
				() -> new MedianPrice(), (i, b) -> (cast i : MedianPrice).update(b))
		};
	}
}
