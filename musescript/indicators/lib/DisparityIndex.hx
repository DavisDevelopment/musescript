package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Disparity Index: how far the current price sits from its own simple
 * moving average, as a percentage of that average.
 *
 * DI = (price - SMA(price, period)) / SMA(price, period) * 100
 *
 * Positive means price is trading above its recent average, negative below.
 */
class DisparityIndex implements MuseIndicator<Float, Float> {
	var sma:Sma;

	public function new(period:Int) {
		sma = new Sma(period);
	}

	public function update(price:Float):Null<Float> {
		var avg = sma.update(price);
		if (avg == null) return null;
		if (avg == 0.0) return 0.0;
		return (price - avg) / avg * 100.0;
	}

	public function reset():Void {
		sma.reset();
	}

	public function warmupPeriod():Int return sma.period;
	public function isReady():Bool return sma.isReady();
	public function name():String return "DisparityIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "disparity_index", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "disparity_index:" + series + ":" + p, series, Math.NaN,
					() -> new DisparityIndex(p), (i, v) -> (cast i : DisparityIndex).update(v));
			}
		};
	}
}
