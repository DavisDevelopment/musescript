package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Candle Volume: a stateless pass-through of the bar's volume field, exposed
 * as its own indicator so volume can be composed inside expressions that
 * expect an indicator call (e.g. feeding a downstream MA/z-score builtin)
 * rather than a bare bar-field identifier.
 */
class CandleVolume implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		return bar.volume;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "CandleVolume";

	public static function spec():IndicatorSpec {
		return {
			name: "candle_volume", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "candle_volume", Math.NaN,
				() -> new CandleVolume(), (i, b) -> (cast i : CandleVolume).update(b))
		};
	}
}
