package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Projection Bands output: upper/middle/lower. */
typedef ProjectionBandsOutput = {
	/** Upper band: the maximum forward-projected high in the window. */
	var upper:Float;
	/** Middle line: the midpoint of the upper and lower bands. */
	var middle:Float;
	/** Lower band: the minimum forward-projected low in the window. */
	var lower:Float;
}

/**
 * Projection Bands (Mel Widner) — ported from wickra-core's `ProjectionBands`
 * (vendor/wickra/crates/wickra-core/src/indicators/projection_bands.rs).
 *
 * Fits a separate linear regression to the highs and to the lows over the
 * last `period` bars, then slides every bar's high and low forward to the
 * current bar along its own slope. The upper band is the max of the
 * projected highs, the lower band the min of the projected lows:
 *
 *   slope_h = OLS slope of (x, high) over the window
 *   slope_l = OLS slope of (x, low)  over the window
 *   upper   = max over i of [ high_i + slope_h · (period−1−i) ]
 *   lower   = min over i of [ low_i  + slope_l · (period−1−i) ]
 *   middle  = (upper + lower) / 2
 *
 * Reference: "Projection Bands and the Projection Oscillator", Technical
 * Analysis of Stocks & Commodities, May 1995.
 */
class ProjectionBands implements MuseIndicator<Bar, ProjectionBandsOutput> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;
	var sumX:Float;
	var sumXx:Float;

	public function new(period:Int) {
		if (period < 2) throw "ProjectionBands: period must be >= 2";
		this.period = period;
		var n:Float = period;
		sumX = n * (n - 1.0) / 2.0;
		sumXx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;
		highs = [];
		lows = [];
	}

	/** OLS slope of (0..period, values) over the live window. */
	function slope(values:Array<Float>):Float {
		var n:Float = period;
		var sumY = 0.0;
		var sumXy = 0.0;
		for (i in 0...values.length) {
			sumY += values[i];
			sumXy += i * values[i];
		}
		var denom = n * sumXx - sumX * sumX;
		return (n * sumXy - sumX * sumY) / denom;
	}

	public function update(bar:Bar):Null<ProjectionBandsOutput> {
		if (highs.length == period) {
			highs.shift();
			lows.shift();
		}
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period) return null;

		var slopeH = slope(highs);
		var slopeL = slope(lows);
		var last:Float = period - 1;

		var upper = Math.NEGATIVE_INFINITY;
		var lower = Math.POSITIVE_INFINITY;
		for (i in 0...period) {
			var forward = last - i;
			var projectedHigh = highs[i] + slopeH * forward;
			var projectedLow = lows[i] + slopeL * forward;
			if (projectedHigh > upper) upper = projectedHigh;
			if (projectedLow < lower) lower = projectedLow;
		}

		return {upper: upper, middle: (upper + lower) / 2.0, lower: lower};
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "ProjectionBands";

	public static function spec():IndicatorSpec {
		return {
			name: "projection_bands", args: [TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var key = "projection_bands:" + p;
				return IndicatorCache.evalBar(h, key, {upper: Math.NaN, middle: Math.NaN, lower: Math.NaN},
					() -> new ProjectionBands(p), (i, b) -> (cast i : ProjectionBands).update(b));
			}
		};
	}
}
