package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Instantaneous Trendline: a near-zero-lag trendline built from a
 * fixed-alpha recursive smoother tuned to track price without the delay of
 * a conventional MA.
 *
 * IT_t = (alpha - alpha^2/4)*price_t + 0.5*alpha^2*price_{t-1}
 *        - (alpha - 0.75*alpha^2)*price_{t-2}
 *        + 2*(1-alpha)*IT_{t-1} - (1-alpha)^2*IT_{t-2}
 *
 * Seeded for the first two bars with the simple average
 * `(price_t + 2*price_{t-1} + price_{t-2}) / 4` (Ehlers' own seeding
 * recipe), once 3 prices are available.
 */
class InstantaneousTrendline implements MuseIndicator<Float, Float> {
	var alpha:Float;
	var priceHist:Array<Float>;
	var itHist:Array<Float>;
	var count:Int;

	public function new(alpha:Float = 0.07) {
		if (!Math.isFinite(alpha) || alpha <= 0.0 || alpha >= 1.0) throw "InstantaneousTrendline: alpha must be in (0, 1)";
		this.alpha = alpha;
		priceHist = [0.0, 0.0];
		itHist = [0.0, 0.0];
		count = 0;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		count++;

		var it:Float;
		if (count < 3) {
			it = price;
		} else {
			var a2 = alpha * alpha;
			it = (alpha - a2 / 4.0) * price
				+ 0.5 * a2 * priceHist[1]
				- (alpha - 0.75 * a2) * priceHist[0]
				+ 2.0 * (1.0 - alpha) * itHist[1]
				- (1.0 - alpha) * (1.0 - alpha) * itHist[0];
		}
		if (count == 3) it = (price + 2.0 * priceHist[1] + priceHist[0]) / 4.0;

		priceHist[0] = priceHist[1];
		priceHist[1] = price;
		itHist[0] = itHist[1];
		itHist[1] = it;

		if (count < 3) return null;
		return it;
	}

	public function reset():Void {
		priceHist = [0.0, 0.0];
		itHist = [0.0, 0.0];
		count = 0;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return count >= 3;
	public function name():String return "InstantaneousTrendline";

	public static function spec():IndicatorSpec {
		return {
			name: "instantaneous_trendline", args: [TSeries, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var alpha = IndicatorCache.floatArg(args, 1, 0.07);
				return IndicatorCache.evalSeries(h, "instantaneous_trendline:" + series + ":" + alpha, series, Math.NaN,
					() -> new InstantaneousTrendline(alpha), (i, v) -> (cast i : InstantaneousTrendline).update(v));
			}
		};
	}
}
