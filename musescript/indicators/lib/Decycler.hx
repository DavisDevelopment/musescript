package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Decycler: price with its dominant short-cycle noise removed via a
 * 2-pole high-pass filter, leaving only the underlying trend.
 *
 * alpha1 = (cos(2*pi/period) + sin(2*pi/period) - 1) / cos(2*pi/period)
 * HP_t   = (1 - alpha1/2)^2 * (price_t - 2*price_{t-1} + price_{t-2})
 *          + 2*(1-alpha1)*HP_{t-1} - (1-alpha1)^2*HP_{t-2}
 * Decycler = price_t - HP_t
 *
 * (Ehlers, "Cycle Analytics for Traders".) `HP` (and the price history it
 * needs) is seeded to 0 for the first two bars, matching Ehlers' own
 * reference implementations.
 */
class Decycler implements MuseIndicator<Float, Float> {
	var alpha1:Float;
	var oneMinusAlpha:Float;
	var priceHist:Array<Float>;
	var hpHist:Array<Float>;
	var count:Int;

	public function new(period:Int) {
		if (period < 3) throw "Decycler: period must be >= 3";
		var w = 2.0 * Math.PI / period;
		alpha1 = (Math.cos(w) + Math.sin(w) - 1.0) / Math.cos(w);
		oneMinusAlpha = 1.0 - alpha1;
		priceHist = [0.0, 0.0];
		hpHist = [0.0, 0.0];
		count = 0;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		count++;

		var hp = if (count < 3) {
			0.0;
		} else {
			var c1 = (1.0 - alpha1 / 2.0);
			c1 * c1 * (price - 2.0 * priceHist[1] + priceHist[0])
				+ 2.0 * oneMinusAlpha * hpHist[1]
				- oneMinusAlpha * oneMinusAlpha * hpHist[0];
		}

		priceHist[0] = priceHist[1];
		priceHist[1] = price;
		hpHist[0] = hpHist[1];
		hpHist[1] = hp;

		if (count < 3) return null;
		return price - hp;
	}

	public function reset():Void {
		priceHist = [0.0, 0.0];
		hpHist = [0.0, 0.0];
		count = 0;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return count >= 3;
	public function name():String return "Decycler";

	public static function spec():IndicatorSpec {
		return {
			name: "decycler", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "decycler:" + series + ":" + p, series, Math.NaN,
					() -> new Decycler(p), (i, v) -> (cast i : Decycler).update(v));
			}
		};
	}
}
