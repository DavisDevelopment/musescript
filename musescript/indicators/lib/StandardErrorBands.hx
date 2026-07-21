package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Standard Error Bands output: regression endpoint ± multiplier · stderr. */
typedef StandardErrorBandsOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Standard Error Bands — ported from wickra-core's `StandardErrorBands`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/standard_error_bands.rs).
 *
 * Linear-regression line wrapped by the standard error of the fit:
 *
 *   fit y = a + b·x by OLS over the last `period` closes
 *   stderr = sqrt( Σ residual² / (period − 2) )
 *   middle = a + b · (period − 1)
 *   upper  = middle + multiplier · stderr
 *   lower  = middle − multiplier · stderr
 *
 * Uses the n − 2 OLS divisor (one degree of freedom each for slope and
 * intercept), a slightly wider channel than the population-stddev LinReg
 * Channel. Jon Andersen's original publication pairs the bands with
 * multiplier = 2.0; this implementation reports the raw (unsmoothed) bands.
 */
class StandardErrorBands implements MuseIndicator<Float, StandardErrorBandsOutput> {
	var period:Int;
	var multiplier:Float;
	var window:Array<Float>;
	var sumX:Float;
	var sumXx:Float;

	public function new(period:Int, multiplier:Float) {
		if (period < 3) throw "StandardErrorBands: period must be >= 3";
		if (!Math.isFinite(multiplier) || multiplier <= 0.0)
			throw "StandardErrorBands: multiplier must be positive and finite";
		this.period = period;
		this.multiplier = multiplier;
		var n:Float = period;
		sumX = n * (n - 1.0) / 2.0;
		sumXx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;
		window = [];
	}

	public function update(value:Float):Null<StandardErrorBandsOutput> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) window.shift();
		window.push(value);
		if (window.length < period) return null;
		var n:Float = period;
		var sumY = 0.0;
		var sumXy = 0.0;
		for (i in 0...window.length) {
			var x:Float = i;
			sumY += window[i];
			sumXy += x * window[i];
		}
		var denom = n * sumXx - sumX * sumX;
		var slope = (n * sumXy - sumX * sumY) / denom;
		var intercept = (sumY - slope * sumX) / n;

		var sse = 0.0;
		for (i in 0...window.length) {
			var fitted = intercept + slope * i;
			var r = window[i] - fitted;
			sse += r * r;
		}
		// OLS standard error with n − 2 degrees of freedom; n − 2 >= 1
		// because the constructor enforces period >= 3.
		var stderr = Math.sqrt(sse / (n - 2.0));
		var middle = intercept + slope * (n - 1.0);
		return {
			upper: middle + multiplier * stderr,
			middle: middle,
			lower: middle - multiplier * stderr
		};
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "StandardErrorBands";

	public static function spec():IndicatorSpec {
		return {
			name: "standard_error_bands", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 21);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "standard_error_bands:" + series + ":" + p + ":" + m;
				return IndicatorCache.evalSeries(h, key, series,
					{ upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new StandardErrorBands(p, m), (i, v) -> (cast i : StandardErrorBands).update(v));
			}
		};
	}
}
