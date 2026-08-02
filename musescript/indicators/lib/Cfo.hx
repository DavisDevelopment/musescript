package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Chande Forecast Oscillator: how far the current price sits from the
 * endpoint of a linear-regression line fit over the trailing `period` bars,
 * as a percentage of price.
 *
 * forecast = linreg(price, period).valueAt(mostRecentBar)   (least-squares fit)
 * CFO = (price - forecast) / price * 100
 *
 * Positive means price is running above its recent linear trend
 * (accelerating), negative means it's lagging the trend.
 */
class Cfo implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "Cfo: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;

		var n = window.length;
		var meanX = (n - 1) / 2.0;
		var meanY = 0.0;
		for (y in window) meanY += y;
		meanY /= n;

		var num = 0.0;
		var den = 0.0;
		for (i in 0...n) {
			var dx = i - meanX;
			num += dx * (window.oldest(i) - meanY);
			den += dx * dx;
		}
		if (den == 0.0) return 0.0;
		var slope = num / den;
		var intercept = meanY - slope * meanX;
		var forecast = intercept + slope * (n - 1);

		if (price == 0.0) return 0.0;
		return (price - forecast) / price * 100.0;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Cfo";

	public static function spec():IndicatorSpec {
		return {
			name: "cfo", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "cfo:" + series + ":" + p, series, Math.NaN,
					() -> new Cfo(p), (i, v) -> (cast i : Cfo).update(v));
			}
		};
	}
}
