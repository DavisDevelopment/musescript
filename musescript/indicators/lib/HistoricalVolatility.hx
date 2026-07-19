package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Historical (realized) Volatility: the annualized standard deviation of
 * log returns over a trailing window of `period` bars.
 *
 * r_t = ln(price_t / price_{t-1})
 * HV  = stddev(r, period) * sqrt(annualizationFactor)
 *
 * `annualizationFactor` defaults to 252 (daily-bar convention); pass e.g.
 * 252*24 for hourly bars, 1 to leave the result unannualized.
 */
class HistoricalVolatility implements MuseIndicator<Float, Float> {
	var period:Int;
	var annualizationFactor:Float;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;
	var lastPrice:Null<Float>;

	public function new(period:Int, annualizationFactor:Float = 252.0) {
		if (period < 2) throw "HistoricalVolatility: period must be >= 2";
		if (!Math.isFinite(annualizationFactor) || annualizationFactor <= 0.0) {
			throw "HistoricalVolatility: annualizationFactor must be positive and finite";
		}
		this.period = period;
		this.annualizationFactor = annualizationFactor;
		window = [];
		sum = 0.0;
		sumSq = 0.0;
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price) || price <= 0.0) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var r = Math.log(price / lastPrice);
		lastPrice = price;

		if (window.length == period) {
			var old = window.shift();
			sum -= old;
			sumSq -= old * old;
		}
		window.push(r);
		sum += r;
		sumSq += r * r;
		if (window.length < period) return null;

		var mean = sum / period;
		var variance = Math.max(0.0, (sumSq / period) - mean * mean);
		return Math.sqrt(variance) * Math.sqrt(annualizationFactor);
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		sumSq = 0.0;
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "HistoricalVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "historical_volatility", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var af = IndicatorCache.floatArg(args, 2, 252.0);
				var key = "historical_volatility:" + series + ":" + p + ":" + af;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new HistoricalVolatility(p, af), (i, v) -> (cast i : HistoricalVolatility).update(v));
			}
		};
	}
}
