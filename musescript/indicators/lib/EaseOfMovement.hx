package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Ease of Movement: relates a bar's price change to the volume needed to
 * produce it — high volume moving price only a little means price is
 * "resisted"; low volume moving it a lot means it moves "easily".
 *
 * distanceMoved = midpoint_t - midpoint_{t-1}          (midpoint = (H+L)/2)
 * boxRatio      = volume_t / (high_t - low_t)
 * rawEmv        = distanceMoved / boxRatio = distanceMoved * (high - low) / volume
 * EMV           = SMA(rawEmv, period)
 *
 * Falls back to a raw value of 0 on a zero-range or zero-volume bar (no
 * meaningful box ratio).
 */
class EaseOfMovement implements MuseIndicator<Bar, Float> {
	var sma:Sma;
	var hasPrevMid:Bool;
	var prevMid:Float;

	public function new(period:Int) {
		sma = new Sma(period);
		hasPrevMid = false;
		prevMid = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var mid = (bar.high + bar.low) / 2.0;
		var raw = 0.0;
		if (hasPrevMid) {
			var range = bar.high - bar.low;
			if (range > 0.0 && bar.volume > 0.0) {
				raw = (mid - prevMid) * range / bar.volume;
			}
		}
		prevMid = mid;
		hasPrevMid = true;
		return sma.update(raw);
	}

	public function reset():Void {
		sma.reset();
		hasPrevMid = false;
		prevMid = 0.0;
	}

	public function warmupPeriod():Int return sma.period + 1;
	public function isReady():Bool return sma.isReady();
	public function name():String return "EaseOfMovement";

	public static function spec():IndicatorSpec {
		return {
			name: "ease_of_movement", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "ease_of_movement:" + p, Math.NaN,
					() -> new EaseOfMovement(p), (i, b) -> (cast i : EaseOfMovement).update(b));
			}
		};
	}
}
