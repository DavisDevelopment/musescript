package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Cyber Cycle: a low-lag bandpass-style filter that isolates the
 * dominant short-term cycle in price, built from a 4-bar weighted smooth
 * followed by a 2nd-difference recursive filter.
 *
 * Smooth_t = (price_t + 2*price_{t-1} + 2*price_{t-2} + price_{t-3}) / 6
 * Cycle_t  = (1 - 0.5*alpha)^2 * (Smooth_t - 2*Smooth_{t-1} + Smooth_{t-2})
 *            + 2*(1-alpha)*Cycle_{t-1} - (1-alpha)^2*Cycle_{t-2}
 *
 * Seeded for the first few bars (once 3 prices are available) with
 * `(price_t - 2*price_{t-1} + price_{t-2}) / 4`, matching Ehlers' own
 * reference implementation.
 */
class CyberneticCycle implements MuseIndicator<Float, Float> {
	var alpha:Float;
	var priceHist:Array<Float>;
	var smoothHist:Array<Float>;
	var cycleHist:Array<Float>;
	var count:Int;

	public function new(alpha:Float = 0.07) {
		if (!Math.isFinite(alpha) || alpha <= 0.0 || alpha >= 1.0) throw "CyberneticCycle: alpha must be in (0, 1)";
		this.alpha = alpha;
		priceHist = [0.0, 0.0, 0.0];
		smoothHist = [0.0, 0.0];
		cycleHist = [0.0, 0.0];
		count = 0;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		count++;

		priceHist[0] = priceHist[1];
		priceHist[1] = priceHist[2];
		priceHist[2] = price;

		if (count < 4) {
			// Not enough history for the 4-bar smooth yet.
			return null;
		}

		var smooth = (price + 2.0 * priceHist[2] + 2.0 * priceHist[1] + priceHist[0]) / 6.0;

		var cycle:Float;
		if (count < 7) {
			cycle = (price - 2.0 * priceHist[1] + priceHist[0]) / 4.0;
		} else {
			var c1 = 1.0 - 0.5 * alpha;
			var oneMinusAlpha = 1.0 - alpha;
			cycle = c1 * c1 * (smooth - 2.0 * smoothHist[1] + smoothHist[0])
				+ 2.0 * oneMinusAlpha * cycleHist[1]
				- oneMinusAlpha * oneMinusAlpha * cycleHist[0];
		}

		smoothHist[0] = smoothHist[1];
		smoothHist[1] = smooth;
		cycleHist[0] = cycleHist[1];
		cycleHist[1] = cycle;

		return cycle;
	}

	public function reset():Void {
		priceHist = [0.0, 0.0, 0.0];
		smoothHist = [0.0, 0.0];
		cycleHist = [0.0, 0.0];
		count = 0;
	}

	public function warmupPeriod():Int return 4;
	public function isReady():Bool return count >= 4;
	public function name():String return "CyberneticCycle";

	public static function spec():IndicatorSpec {
		return {
			name: "cybernetic_cycle", args: [TSeries, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var alpha = IndicatorCache.floatArg(args, 1, 0.07);
				return IndicatorCache.evalSeries(h, "cybernetic_cycle:" + series + ":" + alpha, series, Math.NaN,
					() -> new CyberneticCycle(alpha), (i, v) -> (cast i : CyberneticCycle).update(v));
			}
		};
	}
}
