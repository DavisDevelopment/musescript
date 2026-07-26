package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Multi-scale Hurst via log-log regression of R/S across nested window sizes
 * (period/4, period/2, period). Falls back to 0.5 when regression is undefined.
 */
class HurstMultiScale implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var lastPrice:Float;
	var hasPrice:Bool;
	var scales:Array<Int>;

	public function new(period:Int) {
		if (period < 16) throw "HurstMultiScale: period must be >= 16";
		this.period = period;
		window = new RingBuffer(period);
		lastPrice = Math.NaN;
		hasPrice = false;
		var s1 = Std.int(period / 4);
		var s2 = Std.int(period / 2);
		if (s1 < 4) s1 = 4;
		scales = [s1, s2, period];
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (!hasPrice) {
			lastPrice = price;
			hasPrice = true;
			return null;
		}
		window.push(price - lastPrice);
		lastPrice = price;
		if (window.length < period) return null;

		var sumX = 0.0;
		var sumY = 0.0;
		var sumXX = 0.0;
		var sumXY = 0.0;
		var n = 0;
		for (si in 0...scales.length) {
			var scale = scales[si];
			var rs = rescaledRange(scale);
			if (!(rs > 0)) continue;
			var x = Math.log(scale);
			var y = Math.log(rs);
			sumX += x;
			sumY += y;
			sumXX += x * x;
			sumXY += x * y;
			n++;
		}
		if (n < 2) return 0.5;
		var denom = n * sumXX - sumX * sumX;
		if (Math.abs(denom) < 1e-18) return 0.5;
		return (n * sumXY - sumX * sumY) / denom;
	}

	function rescaledRange(scale:Int):Float {
		// Newest `scale` returns: at(0)..at(scale-1)
		var mean = 0.0;
		for (i in 0...scale) mean += window.at(i);
		mean /= scale;
		var cum = 0.0;
		var maxY = Math.NEGATIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var sumSq = 0.0;
		// Walk oldest→newest within the scale window for cumulative deviation
		for (i in 0...scale) {
			var r = window.at(scale - 1 - i);
			cum += r - mean;
			if (cum > maxY) maxY = cum;
			if (cum < minY) minY = cum;
			sumSq += (r - mean) * (r - mean);
		}
		var s = Math.sqrt(sumSq / scale);
		if (s == 0.0) return 0.0;
		return (maxY - minY) / s;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		lastPrice = Math.NaN;
		hasPrice = false;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "HurstMultiScale";

	public static function spec():IndicatorSpec {
		return {
			name: "hurst_multiscale", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 64);
				return IndicatorCache.evalSeries(h, "hurst_multiscale:" + series + ":" + p, series, Math.NaN,
					() -> new HurstMultiScale(p), (i, v) -> (cast i : HurstMultiScale).update(v));
			}
		};
	}
}
