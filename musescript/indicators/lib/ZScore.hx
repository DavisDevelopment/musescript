package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Z-Score — ported from wickra-core's `ZScore`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/z_score.rs).
 *
 * How many standard deviations the latest price sits from its rolling mean:
 *
 *   ZScore = (price − SMA(price, n)) / population_stddev(price, n)
 *
 * `+2` means two standard deviations above the recent average — statistically
 * stretched to the upside; `−2` the mirror. A window with zero dispersion (a
 * flat series) yields 0.
 */
class ZScore implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period <= 0) throw "ZScore: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		var wasFull = window.isFull();
		var old = window.push(value);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += value;
		sumSq += value * value;
		if (window.length < period) return null;
		var n:Float = period;
		var mean = sum / n;
		// Population variance E[x²] − E[x]²; clamp away tiny negative drift.
		var variance = sumSq / n - mean * mean;
		if (variance < 0.0) variance = 0.0;
		var std = Math.sqrt(variance);
		if (std == 0.0) {
			// A window with no dispersion: the price is exactly its own mean.
			return 0.0;
		}
		return (value - mean) / std;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "ZScore";

	public static function spec():IndicatorSpec {
		return {
			name: "z_score", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "z_score:" + series + ":" + p, series, Math.NaN,
					() -> new ZScore(p), (i, v) -> (cast i : ZScore).update(v));
			}
		};
	}
}
