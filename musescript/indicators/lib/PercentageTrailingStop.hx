package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Percentage Trailing Stop — a fixed-percentage stop that ratchets with the trend.
 * Ported from wickra-core's `PercentageTrailingStop`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/percentage_trailing_stop.rs).
 *
 * A fixed-percentage stop that ratchets with the trend and flips to the opposite
 * side on a close-through.
 *
 * step = price · percent / 100
 *
 * long:   stop_t = max(stop_{t−1}, close − step)   while close ≥ stop_{t−1}
 * short:  stop_t = min(stop_{t−1}, close + step)   while close ≤ stop_{t−1}
 * flip-to-long  on a close > prev short-stop -> stop = close − step
 * flip-to-short on a close < prev long-stop  -> stop = close + step
 *
 * The first input seeds a long stop `percent` below price. A common configuration
 * is `5.0` (a 5% trail).
 */
class PercentageTrailingStop implements MuseIndicator<Float, Float> {
	var percent:Float;
	var prev_stop:Null<Float>;
	var long:Bool;

	public function new(percent:Float) {
		if (!Math.isFinite(percent) || percent <= 0.0) throw "PercentageTrailingStop: percent must be positive and finite";
		this.percent = percent;
		prev_stop = null;
		long = true;
	}

	public function update(close:Float):Null<Float> {
		if (!Math.isFinite(close)) return null;

		var step = Math.abs(close) * percent / 100.0;
		var stop:Float;
		if (prev_stop != null) {
			var prev = prev_stop;
			if (long) {
				if (close < prev) {
					long = false;
					stop = close + step;
				} else {
					stop = Math.max(prev, close - step);
				}
			} else {
				if (close > prev) {
					long = true;
					stop = close - step;
				} else {
					stop = Math.min(prev, close + step);
				}
			}
		} else {
			stop = close - step;
		}
		prev_stop = stop;
		return stop;
	}

	public function reset():Void {
		prev_stop = null;
		long = true;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return prev_stop != null;
	public function name():String return "PercentageTrailingStop";

	public static function spec():IndicatorSpec {
		return {
			name: "percentage_trailing_stop", args: [TSeries, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.floatArg(args, 1, 5.0);
				return IndicatorCache.evalSeries(h, "percentage_trailing_stop:" + series + ":" + p, series, Math.NaN,
					() -> new PercentageTrailingStop(p), (i, v) -> (cast i : PercentageTrailingStop).update(v));
			}
		};
	}
}
