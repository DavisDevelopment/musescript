package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Wma;
import musescript.types.MuseType;

/**
 * Hull Moving Average: Alan Hull's low-lag average, built by extrapolating a
 * half-period WMA away from a full-period WMA and re-smoothing with a
 * sqrt-period WMA (the original construction `Ehma`/`GeneralizedDema` here
 * echo with EMA instead of WMA).
 *
 * hma = WMA( 2*WMA(price, period/2) - WMA(price, period), round(sqrt(period)) )
 */
class Hma implements MuseIndicator<Float, Float> {
	var halfWma:Wma;
	var fullWma:Wma;
	var smoothWma:Wma;

	public function new(period:Int) {
		if (period < 2) throw "Hma: period must be >= 2";
		var half = Std.int(period / 2);
		if (half < 1) half = 1;
		var smoothPeriod = Math.round(Math.sqrt(period));
		if (smoothPeriod < 1) smoothPeriod = 1;
		halfWma = new Wma(half);
		fullWma = new Wma(period);
		smoothWma = new Wma(smoothPeriod);
	}

	public function update(price:Float):Null<Float> {
		var h = halfWma.update(price);
		var f = fullWma.update(price);
		if (h == null || f == null) return null;
		return smoothWma.update(2.0 * h - f);
	}

	public function reset():Void {
		halfWma.reset();
		fullWma.reset();
		smoothWma.reset();
	}

	public function warmupPeriod():Int return fullWma.period + smoothWma.period;
	public function isReady():Bool return smoothWma.isReady();
	public function name():String return "Hma";

	public static function spec():IndicatorSpec {
		return {
			name: "hma", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "hma:" + series + ":" + p, series, Math.NaN,
					() -> new Hma(p), (i, v) -> (cast i : Hma).update(v));
			}
		};
	}
}
