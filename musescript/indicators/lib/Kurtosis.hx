package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Excess Kurtosis: the 4th standardized moment of the trailing
 * window of `period` values, minus 3 (so a normal distribution reads 0 —
 * the same excess-kurtosis convention `JarqueBera` uses internally).
 *
 * K = m4 / m2^2 - 3
 *
 * Positive means fatter tails / more outlier-prone than Gaussian; negative
 * means thinner tails. Falls back to 0 when the window has zero variance
 * (degenerate — kurtosis undefined for a constant series).
 */
class Kurtosis implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 4) throw "Kurtosis: period must be >= 4";
		this.period = period;
		window = [];
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;

		var n = window.length;
		var mean = 0.0;
		for (v in window) mean += v;
		mean /= n;

		var m2 = 0.0, m4 = 0.0;
		for (v in window) {
			var d = v - mean;
			var d2 = d * d;
			m2 += d2;
			m4 += d2 * d2;
		}
		m2 /= n; m4 /= n;
		if (m2 == 0.0) return 0.0;
		return m4 / (m2 * m2) - 3.0;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Kurtosis";

	public static function spec():IndicatorSpec {
		return {
			name: "kurtosis", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "kurtosis:" + series + ":" + p, series, Math.NaN,
					() -> new Kurtosis(p), (i, v) -> (cast i : Kurtosis).update(v));
			}
		};
	}
}
