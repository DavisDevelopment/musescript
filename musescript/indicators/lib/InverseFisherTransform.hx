package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/**
 * Inverse Fisher Transform of RSI (Ehlers/Sluggo): compresses RSI's
 * distribution toward -1/+1, making its transitions sharper and its
 * midpoint (0) crossings cleaner turning-point signals than raw RSI's
 * 50-line crossings.
 *
 * v = 0.1 * (RSI(price, period) - 50)
 * IFT = (exp(2*v) - 1) / (exp(2*v) + 1)          (== tanh(v))
 *
 * Output is bounded in (-1, +1).
 */
class InverseFisherTransform implements MuseIndicator<Float, Float> {
	var rsi:Rsi;

	public function new(period:Int) {
		rsi = new Rsi(period);
	}

	public function update(price:Float):Null<Float> {
		var r = rsi.update(price);
		if (r == null) return null;
		var v = 0.1 * (r - 50.0);
		var e2v = Math.exp(2.0 * v);
		return (e2v - 1.0) / (e2v + 1.0);
	}

	public function reset():Void {
		rsi.reset();
	}

	public function warmupPeriod():Int return rsi.warmupPeriod();
	public function isReady():Bool return rsi.isReady();
	public function name():String return "InverseFisherTransform";

	public static function spec():IndicatorSpec {
		return {
			name: "inverse_fisher_transform", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "inverse_fisher_transform:" + series + ":" + p, series, Math.NaN,
					() -> new InverseFisherTransform(p), (i, v) -> (cast i : InverseFisherTransform).update(v));
			}
		};
	}
}
