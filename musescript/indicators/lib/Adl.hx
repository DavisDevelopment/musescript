package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Accumulation/Distribution Line — ported from wickra-core's `Adl`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adl.rs).
 *
 * Marc Chaikin's cumulative volume-flow indicator. Each bar contributes a
 * money-flow volume weighted by where the close fell within the bar's range.
 *
 * MFM_t = ((close − low) − (high − close)) / (high − low)   (−1..+1)
 * MFV_t = MFM_t · volume_t
 * ADL_t = ADL_{t−1} + MFV_t
 */
class Adl implements MuseIndicator<Bar, Float> {
	var total:Float;
	var hasEmitted:Bool;

	public function new() {
		total = 0.0;
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		var range = bar.high - bar.low;
		var mfv = if (range == 0.0) {
			// A zero-range bar carries no positional information.
			0.0;
		} else {
			var mfm = ((bar.close - bar.low) - (bar.high - bar.close)) / range;
			mfm * bar.volume;
		}
		total += mfv;
		hasEmitted = true;
		return total;
	}

	public function reset():Void {
		total = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ADL";

	public static function spec():IndicatorSpec {
		return {
			name: "adl", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "adl", Math.NaN,
					() -> new Adl(), (i, b) -> (cast i : Adl).update(b));
			}
		};
	}
}
