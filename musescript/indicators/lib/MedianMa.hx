package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Median Moving Average: the rolling median of the trailing `period`
 * values — a robust alternative to `Sma` that ignores single-bar spikes
 * entirely rather than averaging them in.
 */
class MedianMa implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:SortedWindow;

	public function new(period:Int) {
		if (period < 2) throw "MedianMa: period must be >= 2";
		this.period = period;
		window = new SortedWindow(period);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;
		return window.median();
	}

	public function reset():Void {
		window = new SortedWindow(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "MedianMa";

	public static function spec():IndicatorSpec {
		return {
			name: "median_ma", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "median_ma:" + series + ":" + p, series, Math.NaN,
					() -> new MedianMa(p), (i, v) -> (cast i : MedianMa).update(v));
			}
		};
	}
}
