package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Drawdown Duration: the number of bars since the running peak of the input
 * (treated as an equity curve) was last set.
 *
 * 0 on a bar that establishes a new peak; increments by 1 on every bar spent
 * below the peak.
 */
class DrawdownDuration implements MuseIndicator<Float, Float> {
	var peak:Float;
	var duration:Float;
	var hasEmitted:Bool;

	public function new() {
		peak = Math.NEGATIVE_INFINITY;
		duration = 0.0;
		hasEmitted = false;
	}

	public function update(equity:Float):Null<Float> {
		if (!Math.isFinite(equity)) return hasEmitted ? duration : null;
		hasEmitted = true;
		if (equity >= peak) {
			peak = equity;
			duration = 0.0;
		} else {
			duration += 1.0;
		}
		return duration;
	}

	public function reset():Void {
		peak = Math.NEGATIVE_INFINITY;
		duration = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "DrawdownDuration";

	public static function spec():IndicatorSpec {
		return {
			name: "drawdown_duration", args: [TSeries], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "drawdown_duration:" + series, series, Math.NaN,
					() -> new DrawdownDuration(), (i, v) -> (cast i : DrawdownDuration).update(v));
			}
		};
	}
}
