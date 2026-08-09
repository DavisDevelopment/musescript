package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Median Absolute Deviation: a robust (outlier-resistant) dispersion
 * measure over a trailing window of `period` values — the median of the
 * absolute deviations from the window's own median, rather than the mean of
 * squared deviations (stddev's construction).
 *
 * MAD = median( |x_i - median(x)| )
 *
 * The primary window and the abs-dev multiset both use `SortedWindow`. Abs
 * deviations are mid-dependent: when `median()` bits change, every
 * `|x − med|` regenerates, so the abs window is rebuilt from
 * `Math.abs(x - med)` (never ±Δ remapping — same ULP class as AdaptiveLaguerre
 * even-n mid norms). While `med` is bit-stable, surviving abs values stay valid
 * and only the chrono push/evict pair updates.
 */
class MedianAbsoluteDeviation implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:SortedWindow;
	var absDevs:SortedWindow;
	/** Last median whose abs multiset is currently represented in `absDevs`. */
	var lastMed:Float;
	var absReady:Bool;

	public function new(period:Int) {
		if (period < 2) throw "MedianAbsoluteDeviation: period must be >= 2";
		this.period = period;
		window = new SortedWindow(period);
		absDevs = new SortedWindow(period);
		lastMed = 0.0;
		absReady = false;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		window.push(input);
		if (window.length < period) return null;

		var med = window.median();
		// Exact Float gate (not soft epsilon): survivors' stored abs bits remain
		// valid iff median bits are unchanged. JS: do not use Null<Float> for 0.
		if (absReady && absDevs.length == period && med == lastMed) {
			absDevs.push(Math.abs(input - med));
		} else {
			rebuildAbsDevs(med);
		}
		return absDevs.median();
	}

	function rebuildAbsDevs(med:Float):Void {
		absDevs.reset();
		for (i in 0...window.length) {
			absDevs.push(Math.abs(window.oldest(i) - med));
		}
		lastMed = med;
		absReady = true;
	}

	public function reset():Void {
		window = new SortedWindow(period);
		absDevs = new SortedWindow(period);
		lastMed = 0.0;
		absReady = false;
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
