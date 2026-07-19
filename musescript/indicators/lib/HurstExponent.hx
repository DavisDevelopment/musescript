package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hurst Exponent (single-scale rescaled-range estimator): estimates how
 * mean-reverting (H < 0.5), random-walk-like (H ~ 0.5), or trending
 * (H > 0.5) a series has recently been, from the classic R/S statistic over
 * a trailing window of `period` bar-over-bar returns.
 *
 * Y_i = cumulative deviation of returns from their window mean
 * R    = max(Y) - min(Y)                 (rescaled range)
 * S    = stddev(returns, period)
 * H    = ln(R/S) / ln(period)
 *
 * This is a single-window estimate (not a multi-scale log-log regression
 * across several window sizes, which real Hurst estimation typically
 * averages over) — a defensible, well-defined simplification for a
 * streaming single-pass indicator. Falls back to 0.5 (random-walk neutral)
 * when S is zero (a perfectly flat window).
 */
class HurstExponent implements MuseIndicator<Float, Float> {
	var period:Int;
	var lnPeriod:Float;
	var window:Array<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int) {
		if (period < 4) throw "HurstExponent: period must be >= 4";
		this.period = period;
		lnPeriod = Math.log(period);
		window = [];
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var ret = price - lastPrice;
		lastPrice = price;

		if (window.length == period) window.shift();
		window.push(ret);
		if (window.length < period) return null;

		var mean = 0.0;
		for (r in window) mean += r;
		mean /= period;

		var cumDev = 0.0;
		var maxY = Math.NEGATIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var sumSq = 0.0;
		for (r in window) {
			cumDev += r - mean;
			if (cumDev > maxY) maxY = cumDev;
			if (cumDev < minY) minY = cumDev;
			sumSq += (r - mean) * (r - mean);
		}
		var s = Math.sqrt(sumSq / period);
		if (s == 0.0) return 0.5;
		var rs = (maxY - minY) / s;
		if (rs <= 0.0) return 0.5;
		return Math.log(rs) / lnPeriod;
	}

	public function reset():Void {
		window = [];
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "HurstExponent";

	public static function spec():IndicatorSpec {
		return {
			name: "hurst_exponent", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "hurst_exponent:" + series + ":" + p, series, Math.NaN,
					() -> new HurstExponent(p), (i, v) -> (cast i : HurstExponent).update(v));
			}
		};
	}
}
