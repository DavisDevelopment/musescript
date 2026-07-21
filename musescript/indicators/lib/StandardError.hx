package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Standard Error of the rolling least-squares regression — ported from
 * wickra-core's `StandardError`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/standard_error.rs).
 *
 * Over the trailing window indexed x = 0, 1, …, period − 1 the OLS line
 * y = a + b·x is fitted, then:
 *
 *   slope    = (n·Σxy − Σx·Σy) / (n·Σxx − (Σx)²)
 *   SS_total = Σy² − n·ȳ²
 *   RSS      = SS_total − slope² · S_xx
 *   StdErr   = √( RSS / (n − 2) )
 *
 * where S_xx = (n·Σxx − (Σx)²) / n. The textbook standard error of estimate
 * of OLS with n − 2 residual degrees of freedom. O(1) per update: Σx and Σxx
 * depend only on `period` and are precomputed once, while Σy, Σxy and Σy²
 * slide incrementally.
 */
class StandardError implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var sumX:Float;
	/** n·Σxx − (Σx)² — OLS denominator, constant in `period`. */
	var denom:Float;
	var sumY:Float;
	var sumXy:Float;
	var sumYSq:Float;

	public function new(period:Int) {
		if (period < 3) throw "StandardError: period must be >= 3";
		this.period = period;
		var n:Float = period;
		sumX = n * (n - 1.0) / 2.0;
		var sumXx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;
		denom = n * sumXx - sumX * sumX;
		window = [];
		sumY = 0.0;
		sumXy = 0.0;
		sumYSq = 0.0;
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) {
			// Slide: pop oldest, shift indices, then push the new value at index n − 1.
			var y0 = window.shift();
			sumXy = sumXy - sumY + y0;
			sumY -= y0;
			sumYSq -= y0 * y0;
		}
		var k:Float = window.length;
		window.push(value);
		sumY += value;
		sumXy += k * value;
		sumYSq += value * value;

		if (window.length < period) return null;
		var n:Float = period;
		var slope = (n * sumXy - sumX * sumY) / denom;
		var meanY = sumY / n;
		var ssTotal = sumYSq - n * meanY * meanY;
		// S_xx = denom / n
		var sXx = denom / n;
		var rss = ssTotal - slope * slope * sXx;
		if (rss < 0.0) rss = 0.0;
		return Math.sqrt(rss / (n - 2.0));
	}

	public function reset():Void {
		window = [];
		sumY = 0.0;
		sumXy = 0.0;
		sumYSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "StandardError";

	public static function spec():IndicatorSpec {
		return {
			name: "standard_error", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "standard_error:" + series + ":" + p, series, Math.NaN,
					() -> new StandardError(p), (i, v) -> (cast i : StandardError).update(v));
			}
		};
	}
}
