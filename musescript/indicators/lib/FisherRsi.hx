package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/**
 * Fisher-transformed RSI: applies the same Fisher Transform machinery (see
 * `FisherTransform`) to a Wilder RSI series instead of raw price, sharpening
 * RSI's turning points the same way the classic Fisher Transform sharpens
 * price's.
 */
class FisherRsi implements MuseIndicator<Float, Float> {
	var rsi:Rsi;
	var fisher:FisherTransform;

	public function new(rsiPeriod:Int, fisherPeriod:Int) {
		rsi = new Rsi(rsiPeriod);
		fisher = new FisherTransform(fisherPeriod);
	}

	public function update(price:Float):Null<Float> {
		var r = rsi.update(price);
		if (r == null) return null;
		return fisher.update(r);
	}

	public function reset():Void {
		rsi.reset();
		fisher.reset();
	}

	public function warmupPeriod():Int return rsi.warmupPeriod() + fisher.warmupPeriod();
	public function isReady():Bool return fisher.isReady();
	public function name():String return "FisherRsi";

	public static function spec():IndicatorSpec {
		return {
			name: "fisher_rsi", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var rsiPeriod = IndicatorCache.intArg(args, 1, 14);
				var fisherPeriod = IndicatorCache.intArg(args, 2, 10);
				var key = "fisher_rsi:" + series + ":" + rsiPeriod + ":" + fisherPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new FisherRsi(rsiPeriod, fisherPeriod), (i, v) -> (cast i : FisherRsi).update(v));
			}
		};
	}
}
