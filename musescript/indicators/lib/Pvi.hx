package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Positive Volume Index — ported from wickra-core's `Pvi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pvi.rs).
 *
 * Only updates when volume expands:
 *
 *   PVI_t = PVI_{t-1} * (1 + (close_t - close_{t-1}) / close_{t-1})   if volume_t > volume_{t-1}
 *   PVI_t = PVI_{t-1}                                                 otherwise
 *
 * The first bar establishes the baseline at 1000 (Fosback's convention) and
 * emits it. A bar whose previous close is zero contributes no return.
 */
class Pvi implements MuseIndicator<Bar, Float> {
	static inline var STARTING_INDEX = 1000.0;

	var prevClose:Null<Float>;
	var prevVolume:Null<Float>;
	var index:Float;
	var hasEmitted:Bool;
	var baseline:Float;

	public function new(?baseline:Float) {
		this.baseline = baseline != null ? baseline : STARTING_INDEX;
		prevClose = null;
		prevVolume = null;
		index = this.baseline;
		hasEmitted = false;
	}

	/** Current cumulative value if at least one candle has been ingested. */
	public function value():Null<Float> return hasEmitted ? index : null;

	public function update(bar:Bar):Null<Float> {
		if (prevClose != null && prevVolume != null) {
			var pc:Float = prevClose;
			if (bar.volume > prevVolume && pc != 0.0) {
				var ret = (bar.close - pc) / pc;
				index += index * ret;
			}
		}
		prevClose = bar.close;
		prevVolume = bar.volume;
		hasEmitted = true;
		return index;
	}

	public function reset():Void {
		prevClose = null;
		prevVolume = null;
		index = baseline;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "PVI";

	public static function spec():IndicatorSpec {
		return {
			name: "pvi", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "pvi", Math.NaN,
				() -> new Pvi(), (i, b) -> (cast i : Pvi).update(b))
		};
	}
}
