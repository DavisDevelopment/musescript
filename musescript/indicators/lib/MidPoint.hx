package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * MidPoint (TA-Lib `MIDPOINT`): the midpoint of the highest and lowest
 * values of a single series over a trailing window of `period` bars.
 *
 * MidPoint = ( highest(series, period) + lowest(series, period) ) / 2
 */
class MidPoint implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "MidPoint: period must be > 0";
		this.period = period;
		window = new RingBuffer(period);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		window.push(price);
		if (window.length < period) return null;

		var hi = window.oldest(0);
		var lo = window.oldest(0);
		for (v in window) {
			if (v > hi) hi = v;
			if (v < lo) lo = v;
		}
		return (hi + lo) / 2.0;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "MidPoint";

	public static function spec():IndicatorSpec {
		return {
			name: "mid_point", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "mid_point:" + series + ":" + p, series, Math.NaN,
					() -> new MidPoint(p), (i, v) -> (cast i : MidPoint).update(v));
			}
		};
	}
}
