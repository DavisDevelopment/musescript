package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling population standard deviation — ported from wickra-core's `StdDev`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/std_dev.rs).
 *
 *   mean     = (1/n) · Σ price
 *   variance = (1/n) · Σ price² − mean²
 *   StdDev   = √variance
 *
 * This is the POPULATION standard deviation (divisor n, not n − 1) — the
 * same dispersion measure that drives Bollinger Bands. Distinct from
 * `musescript.indicators.prim.StdDev`, which is the SAMPLE (n − 1) primitive
 * used by composites and is not a builtin. Non-finite inputs are ignored and
 * the last computed value is returned instead.
 */
class StdDev implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "StdDev: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; the window is left untouched.
			return last;
		}
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(input);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += input;
		sumSq += input * input;
		if (window.length < period) return null;
		var n:Float = period;
		var mean = sum / n;
		// Clamp floating-point cancellation noise: variance is never negative.
		var variance = sumSq / n - mean * mean;
		if (variance < 0.0) variance = 0.0;
		var sd = Math.sqrt(variance);
		last = sd;
		return sd;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "StdDev";

	public static function spec():IndicatorSpec {
		return {
			name: "std_dev", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "std_dev:" + series + ":" + p, series, Math.NaN,
					() -> new StdDev(p), (i, v) -> (cast i : StdDev).update(v));
			}
		};
	}
}
