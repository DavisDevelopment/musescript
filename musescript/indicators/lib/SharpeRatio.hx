package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling Sharpe Ratio — ported from wickra-core's `SharpeRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/sharpe_ratio.rs).
 *
 * The input is treated as a single period-return. Over the trailing window of
 * `period` returns:
 *
 * Sharpe = (mean(returns) − risk_free_per_period) / stddev(returns)
 *
 * `stddev` is the sample standard deviation (Bessel's `n − 1` denominator).
 * Wickra does not annualise: feed already-annualised returns and an annual
 * risk-free rate if an annualised Sharpe is wanted. A flat window has zero
 * standard deviation and the indicator returns `0.0` rather than NaN.
 * Each `update` is O(1) via running `Σr`, `Σr²` sums.
 */
class SharpeRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var riskFree:Float;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int, riskFree:Float) {
		if (period < 2) throw "SharpeRatio: sharpe ratio needs period >= 2";
		this.period = period;
		this.riskFree = riskFree;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(input);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += input;
		sumSq += input * input;
		if (window.length < period) return null;
		var n = period;
		var mean = sum / n;
		// Sample variance with Bessel's correction.
		var v = sumSq - n * mean * mean;
		if (v < 0.0) v = 0.0;
		var sd = Math.sqrt(v / (n - 1));
		if (sd == 0.0) return 0.0;
		return (mean - riskFree) / sd;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SharpeRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "sharpe_ratio", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var rf = IndicatorCache.floatArg(args, 2, 0.0);
				var key = "sharpe_ratio:" + series + ":" + p + ":" + rf;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new SharpeRatio(p, rf), (i, v) -> (cast i : SharpeRatio).update(v));
			}
		};
	}
}
