package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Step Trailing Stop — ported from wickra-core's `StepTrailingStop`
 * (vendor/wickra/crates/wickra-core/src/indicators/step_trailing_stop.rs).
 *
 * A stop that ratchets in fixed-size discrete steps and flips to the opposite
 * side on a close-through:
 *
 *   long:  stop_t = max(stop_{t−1}, floor((close − step) / step) · step)  while close ≥ stop_{t−1}
 *   short: stop_t = min(stop_{t−1}, ceil((close + step) / step) · step)   while close ≤ stop_{t−1}
 *
 * Quantising the stop to a multiple of `stepSize` keeps the level on a
 * round-number grid. The first input seeds a long stop one step below the
 * snapped close.
 */
class StepTrailingStop implements MuseIndicator<Float, Float> {
	var stepSize:Float;
	var prevStop:Null<Float>;
	var long:Bool;

	public function new(stepSize:Float) {
		if (!Math.isFinite(stepSize) || stepSize <= 0.0) throw "StepTrailingStop: step_size must be positive and finite";
		this.stepSize = stepSize;
		prevStop = null;
		long = true;
	}

	/** A common configuration: a 1.0 step size. */
	public static function classic():StepTrailingStop {
		return new StepTrailingStop(1.0);
	}

	/** Snap down to the nearest step-grid line below `close − step`. */
	inline function snapLong(close:Float):Float {
		return Math.ffloor((close - stepSize) / stepSize) * stepSize;
	}

	/** Snap up to the nearest step-grid line above `close + step`. */
	inline function snapShort(close:Float):Float {
		return Math.fceil((close + stepSize) / stepSize) * stepSize;
	}

	public function update(close:Float):Null<Float> {
		if (!Math.isFinite(close)) return null;
		var stop:Float;
		if (prevStop != null) {
			var prev:Float = prevStop;
			if (long) {
				if (close < prev) {
					long = false;
					stop = snapShort(close);
				} else {
					stop = Math.max(prev, snapLong(close));
				}
			} else if (close > prev) {
				long = true;
				stop = snapLong(close);
			} else {
				stop = Math.min(prev, snapShort(close));
			}
		} else {
			stop = snapLong(close);
		}
		prevStop = stop;
		return stop;
	}

	public function reset():Void {
		prevStop = null;
		long = true;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return prevStop != null;
	public function name():String return "StepTrailingStop";

	public static function spec():IndicatorSpec {
		return {
			name: "step_trailing_stop", args: [TSeries, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var step = IndicatorCache.floatArg(args, 1, 1.0);
				var key = "step_trailing_stop:" + series + ":" + step;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new StepTrailingStop(step), (i, v) -> (cast i : StepTrailingStop).update(v));
			}
		};
	}
}
