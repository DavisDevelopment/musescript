package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling population variance — ported from wickra-core's `Variance`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/variance.rs).
 *
 *   mean     = (1/n) · Σ price
 *   Variance = (1/n) · Σ price² − mean²
 *
 * The second central moment of the rolling distribution (divisor n). Use the
 * `std_dev` builtin when you need the scale-preserving square root instead.
 * Floating-point cancellation is clamped to zero before returning.
 */
class Variance implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Variance: period must be > 0";
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
		var v = sumSq / n - mean * mean;
		return v < 0.0 ? 0.0 : v;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Variance";

	public static function spec():IndicatorSpec {
		return {
			name: "variance", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "variance:" + series + ":" + p, series, Math.NaN,
					() -> new Variance(p), (i, v) -> (cast i : Variance).update(v));
			}
		};
	}
}
