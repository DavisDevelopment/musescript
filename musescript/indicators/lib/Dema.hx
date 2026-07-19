package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Double Exponential Moving Average (Mulloy): a reduced-lag EMA formed by
 * running a second EMA over the first and extrapolating away the remaining lag.
 *
 * DEMA = 2 * EMA(price, period) - EMA(EMA(price, period), period)
 */
class Dema implements MuseIndicator<Float, Float> {
	var ema1:Ema;
	var ema2:Ema;

	public function new(period:Int) {
		ema1 = new Ema(period);
		ema2 = new Ema(period);
	}

	public function update(price:Float):Null<Float> {
		var e1 = ema1.update(price);
		if (e1 == null) return null;
		var e2 = ema2.update(e1);
		if (e2 == null) return null;
		return 2.0 * e1 - e2;
	}

	public function reset():Void {
		ema1.reset();
		ema2.reset();
	}

	public function warmupPeriod():Int return ema1.period * 2 - 1;
	public function isReady():Bool return ema2.isReady();
	public function name():String return "DEMA";

	public static function spec():IndicatorSpec {
		return {
			name: "dema", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "dema:" + series + ":" + p, series, Math.NaN,
					() -> new Dema(p), (i, v) -> (cast i : Dema).update(v));
			}
		};
	}
}
