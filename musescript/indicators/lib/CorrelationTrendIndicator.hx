package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Correlation Trend Indicator: the Pearson correlation coefficient
 * between price and a simple ascending time index over a trailing window of
 * `period` bars — a direct measure of how "trend-like" (linear) recent price
 * action has been.
 *
 * CTI = corr(price, [1, 2, ..., period]) in [-1, +1]
 *
 * Near +1 means price has been rising in an almost-straight line; near -1
 * means falling in an almost-straight line; near 0 means no linear trend
 * (choppy/range-bound).
 */
class CorrelationTrendIndicator implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "CorrelationTrendIndicator: period must be >= 2";
		this.period = period;
		window = new RingBuffer(period);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;

		var n = window.length;
		var meanX = (n + 1) / 2.0; // x = 1..n
		var meanY = 0.0;
		for (y in window) meanY += y;
		meanY /= n;

		var covXY = 0.0;
		var varX = 0.0;
		var varY = 0.0;
		for (i in 0...n) {
			var x = (i + 1) - meanX;
			var y = window.oldest(i) - meanY;
			covXY += x * y;
			varX += x * x;
			varY += y * y;
		}
		var denom = Math.sqrt(varX * varY);
		if (denom == 0.0) return 0.0;
		return covXY / denom;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CorrelationTrendIndicator";

	public static function spec():IndicatorSpec {
		return {
			name: "correlation_trend_indicator", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "correlation_trend_indicator:" + series + ":" + p, series, Math.NaN,
					() -> new CorrelationTrendIndicator(p), (i, v) -> (cast i : CorrelationTrendIndicator).update(v));
			}
		};
	}
}
