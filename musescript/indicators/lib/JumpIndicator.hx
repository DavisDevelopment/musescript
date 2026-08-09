package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Jump Indicator: flags a bar whose return is a statistical outlier
 * relative to the recent (prior) volatility regime — a simple
 * threshold-based jump/discontinuity detector in the spirit of the
 * bipower-variation jump-detection literature (see `BipowerVariation`).
 *
 * ret_t   = price_t - price_{t-1}
 * sigma_t = stddev(returns over the PRIOR `period` bars, excluding ret_t)
 * output  = 1.0 if |ret_t| > threshold * sigma_t, else 0.0
 *
 * Falls back to 0.0 while the prior-return window is still warming up (no
 * baseline volatility to compare against yet) or when it has zero variance.
 */
class JumpIndicator implements MuseIndicator<Float, Float> {
	var period:Int;
	var threshold:Float;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;
	var lastPrice:Null<Float>;

	public function new(period:Int, threshold:Float) {
		if (period < 2) throw "JumpIndicator: period must be >= 2";
		if (!Math.isFinite(threshold) || threshold <= 0.0) throw "JumpIndicator: threshold must be positive and finite";
		this.period = period;
		this.threshold = threshold;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var ret = price - lastPrice;
		lastPrice = price;

		var wasReady = window.length == period;
		var result = 0.0;
		if (wasReady) {
			var mean = sum / period;
			var variance = Math.max(0.0, (sumSq / period) - mean * mean);
			var sigma = Math.sqrt(variance);
			if (sigma > 0.0 && Math.abs(ret) > threshold * sigma) result = 1.0;
		}

		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(ret);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += ret;
		sumSq += ret * ret;

		return wasReady ? result : null;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 2;
	public function isReady():Bool return window.length == period;
	public function name():String return "JumpIndicator";

	public static function spec():IndicatorSpec {
		return {
			name: "jump_indicator", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var t = IndicatorCache.floatArg(args, 2, 3.0);
				var key = "jump_indicator:" + series + ":" + p + ":" + t;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new JumpIndicator(p, t), (i, v) -> (cast i : JumpIndicator).update(v));
			}
		};
	}
}
