package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * M2 Measure (Modigliani-Modigliani): a risk-adjusted return that rescales
 * the strategy's own Sharpe ratio to a target volatility, expressing
 * performance in the same units as a plain return rather than a unitless
 * ratio.
 *
 * Sharpe = (mean(return, period) - riskFree) / stddev(return, period)
 * M2     = riskFree + Sharpe * targetVol
 *
 * `targetVol` is typically a benchmark's volatility, letting two strategies
 * with different risk levels be compared on an apples-to-apples return
 * basis. Falls back to `riskFree` when the window's stddev is exactly zero
 * (a perfectly flat return series — Sharpe undefined).
 */
class M2Measure implements MuseIndicator<Float, Float> {
	var period:Int;
	var riskFree:Float;
	var targetVol:Float;
	var window:RingBuffer<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int, riskFree:Float, targetVol:Float) {
		if (period < 2) throw "M2Measure: period must be >= 2";
		if (!Math.isFinite(targetVol) || targetVol < 0.0) throw "M2Measure: targetVol must be non-negative and finite";
		this.period = period;
		this.riskFree = riskFree;
		this.targetVol = targetVol;
		window = new RingBuffer(period);
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var ret = lastPrice != 0.0 ? (price - lastPrice) / lastPrice : 0.0;
		lastPrice = price;

		window.push(ret);
		if (window.length < period) return null;

		var mean = 0.0;
		for (r in window) mean += r;
		mean /= period;
		var variance = 0.0;
		for (r in window) variance += (r - mean) * (r - mean);
		variance /= period;
		var sd = Math.sqrt(variance);

		if (sd == 0.0) return riskFree;
		var sharpe = (mean - riskFree) / sd;
		return riskFree + sharpe * targetVol;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "M2Measure";

	public static function spec():IndicatorSpec {
		return {
			name: "m2_measure", args: [TSeries, TWindow, TScalar, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				var riskFree = IndicatorCache.floatArg(args, 2, 0.0);
				var targetVol = IndicatorCache.floatArg(args, 3, 0.01);
				var key = "m2_measure:" + series + ":" + p + ":" + riskFree + ":" + targetVol;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new M2Measure(p, riskFree, targetVol), (i, v) -> (cast i : M2Measure).update(v));
			}
		};
	}
}
