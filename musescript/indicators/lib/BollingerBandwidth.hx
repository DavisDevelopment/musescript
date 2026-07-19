package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.lib.Bollinger.BollingerOutput;
import musescript.types.MuseType;

/**
 * Bollinger Bandwidth: the width of the Bollinger Bands normalized by the
 * middle band, a standard measure of relative volatility / band-squeeze.
 *
 * Bandwidth = (upper - lower) / middle
 *
 * Falls back to 0 when the middle band is exactly zero (undefined ratio).
 */
class BollingerBandwidth implements MuseIndicator<Float, Float> {
	var bb:Bollinger;

	public function new(period:Int, numStdDev:Float) {
		bb = new Bollinger(period, numStdDev);
	}

	public function update(input:Float):Null<Float> {
		var out = bb.update(input);
		if (out == null) return null;
		if (out.middle == 0.0) return 0.0;
		return (out.upper - out.lower) / out.middle;
	}

	public function reset():Void {
		bb.reset();
	}

	public function warmupPeriod():Int return bb.warmupPeriod();
	public function isReady():Bool return bb.isReady();
	public function name():String return "BollingerBandwidth";

	public static function spec():IndicatorSpec {
		return {
			name: "bollinger_bandwidth", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var k = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "bollinger_bandwidth:" + series + ":" + p + ":" + k;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new BollingerBandwidth(p, k), (i, v) -> (cast i : BollingerBandwidth).update(v));
			}
		};
	}
}
