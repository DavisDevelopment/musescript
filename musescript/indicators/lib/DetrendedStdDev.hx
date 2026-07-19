package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Detrended Standard Deviation: the rolling stddev of the *detrended* price
 * series (price minus its own trailing SMA), rather than of raw price —
 * isolating dispersion around the local trend from the trend's own drift.
 *
 * detrended_t = price_t - SMA(price, period)_t
 * DetrendedStdDev = stddev(detrended, period)
 */
class DetrendedStdDev implements MuseIndicator<Float, Float> {
	var trendSma:Sma;
	var period:Int;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period < 2) throw "DetrendedStdDev: period must be >= 2";
		this.period = period;
		trendSma = new Sma(period);
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function update(price:Float):Null<Float> {
		var avg = trendSma.update(price);
		if (avg == null) return null;
		var detrended = price - avg;

		if (window.length == period) {
			var old = window.shift();
			sum -= old;
			sumSq -= old * old;
		}
		window.push(detrended);
		sum += detrended;
		sumSq += detrended * detrended;
		if (window.length < period) return null;

		var mean = sum / period;
		var variance = Math.max(0.0, (sumSq / period) - mean * mean);
		return Math.sqrt(variance);
	}

	public function reset():Void {
		trendSma.reset();
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period * 2 - 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "DetrendedStdDev";

	public static function spec():IndicatorSpec {
		return {
			name: "detrended_std_dev", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "detrended_std_dev:" + series + ":" + p, series, Math.NaN,
					() -> new DetrendedStdDev(p), (i, v) -> (cast i : DetrendedStdDev).update(v));
			}
		};
	}
}
