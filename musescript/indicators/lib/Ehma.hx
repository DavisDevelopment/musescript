package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Exponential Hull Moving Average: the Hull MA's "reduce lag by
 * extrapolating from a half-period average" construction, applied with EMAs
 * in place of Hull's original WMAs.
 *
 * ehma = EMA( 2*EMA(price, period/2) - EMA(price, period), round(sqrt(period)) )
 */
class Ehma implements MuseIndicator<Float, Float> {
	var halfEma:Ema;
	var fullEma:Ema;
	var smoothEma:Ema;

	public function new(period:Int) {
		if (period < 2) throw "Ehma: period must be >= 2";
		var half = Std.int(period / 2);
		if (half < 1) half = 1;
		var smoothPeriod = Math.round(Math.sqrt(period));
		if (smoothPeriod < 1) smoothPeriod = 1;
		halfEma = new Ema(half);
		fullEma = new Ema(period);
		smoothEma = new Ema(smoothPeriod);
	}

	public function update(price:Float):Null<Float> {
		var h = halfEma.update(price);
		var f = fullEma.update(price);
		if (h == null || f == null) return null;
		return smoothEma.update(2.0 * h - f);
	}

	public function reset():Void {
		halfEma.reset();
		fullEma.reset();
		smoothEma.reset();
	}

	public function warmupPeriod():Int return fullEma.period + smoothEma.period;
	public function isReady():Bool return smoothEma.isReady();
	public function name():String return "Ehma";

	public static function spec():IndicatorSpec {
		return {
			name: "ehma", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "ehma:" + series + ":" + p, series, Math.NaN,
					() -> new Ehma(p), (i, v) -> (cast i : Ehma).update(v));
			}
		};
	}
}
