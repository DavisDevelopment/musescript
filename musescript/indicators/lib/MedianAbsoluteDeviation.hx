package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Median Absolute Deviation: a robust (outlier-resistant) dispersion
 * measure over a trailing window of `period` values — the median of the
 * absolute deviations from the window's own median, rather than the mean of
 * squared deviations (stddev's construction).
 *
 * MAD = median( |x_i - median(x)| )
 */
class MedianAbsoluteDeviation implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "MedianAbsoluteDeviation: period must be >= 2";
		this.period = period;
		window = [];
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;

		var med = median(window);
		var deviations = [for (v in window) Math.abs(v - med)];
		return median(deviations);
	}

	static function median(vals:Array<Float>):Float {
		var sorted = vals.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var n = sorted.length;
		if (n % 2 == 1) return sorted[Std.int(n / 2)];
		return (sorted[Std.int(n / 2) - 1] + sorted[Std.int(n / 2)]) / 2.0;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "MedianAbsoluteDeviation";

	public static function spec():IndicatorSpec {
		return {
			name: "median_absolute_deviation", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "median_absolute_deviation:" + series + ":" + p, series, Math.NaN,
					() -> new MedianAbsoluteDeviation(p), (i, v) -> (cast i : MedianAbsoluteDeviation).update(v));
			}
		};
	}
}
