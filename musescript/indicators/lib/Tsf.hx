package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Time Series Forecast (TSF) — ported from wickra-core's `Tsf`
 * (vendor/wickra/crates/wickra-core/src/indicators/tsf.rs).
 *
 * The rolling least-squares line projected one bar past the window. Over the
 * last `period` inputs indexed `x = 0..period−1`, fit `y = a + b·x` by OLS
 * and report the line's value at `x = period`:
 *
 * b (slope)     = (n·Σxy − Σx·Σy) / (n·Σxx − (Σx)²)
 * a (intercept) = (Σy − b·Σx) / n
 * TSF           = a + b·period
 *
 * Where LinearRegression evaluates the fit at the current bar, TSF advances
 * it one further bar — a trend-following one-step-ahead forecast. Each
 * update is O(1) via the identity `Σxy' = Σxy − Σy + y0` on window slide.
 */
class Tsf implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sumX:Float;
	var denom:Float;
	var sumY:Float;
	var sumXy:Float;

	public function new(period:Int) {
		if (period < 2) throw "Tsf: time series forecast needs period >= 2";
		this.period = period;
		var n:Float = period;
		sumX = n * (n - 1.0) / 2.0;
		var sumXx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;
		denom = n * sumXx - sumX * sumX;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var k:Float = wasFull ? period - 1 : window.length;
		var y0 = window.push(value);
		if (wasFull) {
			sumXy = sumXy - sumY + y0;
			sumY -= y0;
		}
		sumY += value;
		sumXy += k * value;

		if (window.length < period) return null;
		var n:Float = period;
		var slope = (n * sumXy - sumX * sumY) / denom;
		var intercept = (sumY - slope * sumX) / n;
		return intercept + slope * n;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sumY = 0.0;
		sumXy = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "TSF";

	public static function spec():IndicatorSpec {
		return {
			name: "tsf", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "tsf:" + series + ":" + p, series, Math.NaN,
					() -> new Tsf(p), (i, v) -> (cast i : Tsf).update(v));
			}
		};
	}
}
