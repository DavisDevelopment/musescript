package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Negative Volume Index: a cumulative index that only updates on bars where
 * volume *fell* from the prior bar, on the premise that "smart money" moves
 * are more visible on quiet, low-volume days.
 *
 * NVI_t = NVI_{t-1} * (1 + (close_t - close_{t-1}) / close_{t-1})   if volume_t < volume_{t-1}
 *       = NVI_{t-1}                                                 otherwise
 *
 * Seeded at 1000 (the traditional NVI starting value) on the first bar.
 */
class Nvi implements MuseIndicator<Bar, Float> {
	var value:Float;
	var hasPrev:Bool;
	var prevClose:Float;
	var prevVolume:Float;

	public function new() {
		value = 1000.0;
		hasPrev = false;
		prevClose = 0.0;
		prevVolume = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		if (!hasPrev) {
			prevClose = bar.close;
			prevVolume = bar.volume;
			hasPrev = true;
			return value;
		}

		if (bar.volume < prevVolume && prevClose != 0.0) {
			value = value * (1.0 + (bar.close - prevClose) / prevClose);
		}
		prevClose = bar.close;
		prevVolume = bar.volume;
		return value;
	}

	public function reset():Void {
		value = 1000.0;
		hasPrev = false;
		prevClose = 0.0;
		prevVolume = 0.0;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasPrev;
	public function name():String return "Nvi";

	public static function spec():IndicatorSpec {
		return {
			name: "nvi", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "nvi", Math.NaN,
				() -> new Nvi(), (i, b) -> (cast i : Nvi).update(b))
		};
	}
}
