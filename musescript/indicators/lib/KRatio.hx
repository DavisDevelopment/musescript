package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kestner's K-Ratio: how smoothly and consistently an equity curve trends
 * upward, measured as the linear-regression slope of log-equity divided by
 * that slope's own standard error (scaled by sqrt(n)), over a trailing
 * window of `period` equity samples.
 *
 * y_i    = ln(equity_i)
 * slope, stdErr(slope) = ordinary least squares fit of y against 0..n-1
 * K-Ratio = slope / stdErr(slope) * sqrt(n)
 *
 * A high K-Ratio means a steady, low-noise uptrend in equity; a volatile or
 * flat/declining equity curve pulls it toward (or below) zero. Falls back
 * to 0 when the regression residuals are exactly zero (a perfectly linear
 * window — no error to divide by, and the slope's significance is
 * undefined in the degenerate case).
 */
class KRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 3) throw "KRatio: period must be >= 3";
		this.period = period;
		window = new RingBuffer(period);
	}

	public function update(equity:Float):Null<Float> {
		if (!Math.isFinite(equity) || equity <= 0.0) return null;
		var y = Math.log(equity);
		window.push(y);
		if (window.length < period) return null;

		var n = window.length;
		var meanX = (n - 1) / 2.0;
		var meanY = 0.0;
		for (v in window) meanY += v;
		meanY /= n;

		var sxx = 0.0;
		var sxy = 0.0;
		for (i in 0...n) {
			var dx = i - meanX;
			sxx += dx * dx;
			sxy += dx * (window.oldest(i) - meanY);
		}
		if (sxx == 0.0) return 0.0;
		var slope = sxy / sxx;

		var sse = 0.0;
		for (i in 0...n) {
			var fitted = meanY + slope * (i - meanX);
			var resid = window.oldest(i) - fitted;
			sse += resid * resid;
		}
		if (n <= 2) return 0.0;
		var residVar = sse / (n - 2);
		var stdErrSlope = Math.sqrt(residVar / sxx);
		if (stdErrSlope == 0.0) return 0.0;
		return (slope / stdErrSlope) * Math.sqrt(n);
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "KRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "k_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "k_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new KRatio(p), (i, v) -> (cast i : KRatio).update(v));
			}
		};
	}
}
