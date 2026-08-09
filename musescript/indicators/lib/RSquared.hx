package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * R² (coefficient of determination) — ported from wickra-core's `RSquared`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/r_squared.rs).
 *
 * Rolling OLS fit over `period` samples. Reports the ratio of variance explained
 * by the line to total variance, clamped to [0, 1]. A perfect linear fit yields 1.0;
 * flat or random walks yield lower values. Useful as a trend-quality filter.
 */
class RSquared implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sumX:Float;
	var denom:Float;
	var sumY:Float;
	var sumXy:Float;
	var sumYsq:Float;

	public function new(period:Int) {
		if (period < 2) throw "RSquared: period must be >= 2";
		this.period = period;

		var n = period;
		var nf = n;
		sumX = nf * (nf - 1.0) / 2.0;
		var sumXx = (nf - 1.0) * nf * (2.0 * nf - 1.0) / 6.0;
		denom = nf * sumXx - sumX * sumX;

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
			sumYsq -= y0 * y0;
		}

		sumY += value;
		sumXy += k * value;
		sumYsq += value * value;

		if (window.length < period) return null;

		var n = period;
		var nf = n;
		var slope = (nf * sumXy - sumX * sumY) / denom;
		var meanY = sumY / nf;
		var ssTotal = Math.max(0.0, sumYsq - nf * meanY * meanY);
		var sXx = denom / nf;
		var ssExplained = slope * slope * sXx;

		if (ssTotal <= 0.0) {
			return 1.0;  // Flat window: trivially perfect fit
		}

		var rsq = ssExplained / ssTotal;
		return Math.max(0.0, Math.min(1.0, rsq));  // Clamp to [0, 1]
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sumY = 0.0;
		sumXy = 0.0;
		sumYsq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "RSquared";

	public static function spec():IndicatorSpec {
		return {
			name: "r_squared", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "r_squared:" + series + ":" + p, series, Math.NaN,
					() -> new RSquared(p), (i, v) -> (cast i : RSquared).update(v));
			}
		};
	}
}
