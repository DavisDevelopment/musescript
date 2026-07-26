package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Hurst Exponent (single-scale R/S) — RingBuffer soak of the classic estimator.
 * See HurstMultiScale for log-log regression across several window sizes.
 */
class HurstExponent implements MuseIndicator<Float, Float> {
	var period:Int;
	var lnPeriod:Float;
	var window:RingBuffer<Float>;
	var lastPrice:Float;
	var hasPrice:Bool;

	public function new(period:Int) {
		if (period < 4) throw "HurstExponent: period must be >= 4";
		this.period = period;
		lnPeriod = Math.log(period);
		window = new RingBuffer(period);
		lastPrice = Math.NaN;
		hasPrice = false;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (!hasPrice) {
			lastPrice = price;
			hasPrice = true;
			return null;
		}
		var ret = price - lastPrice;
		lastPrice = price;
		window.push(ret);
		if (window.length < period) return null;

		var mean = 0.0;
		for (i in 0...window.length) mean += window.at(i);
		mean /= period;

		var cumDev = 0.0;
		var maxY = Math.NEGATIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var sumSq = 0.0;
		for (i in 0...window.length) {
			var r = window.at(i);
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
		window = new RingBuffer(period);
		lastPrice = Math.NaN;
		hasPrice = false;
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
