package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling Pearson skewness — ported from wickra-core's `Skewness`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/skewness.rs).
 *
 * Third standardised central moment of the last `period` values:
 *
 *   mean = (1/n) · Σ x
 *   m2   = (1/n) · Σ (x − mean)²        // population variance
 *   m3   = (1/n) · Σ (x − mean)³        // third central moment
 *   Skew = m3 / m2^(3/2)
 *
 * Positive means the right tail is heavier, negative the left. This is the
 * population (Pearson) definition with divisor n. O(1) per update via three
 * running sums (Σx, Σx², Σx³) and binomial-expansion identities. A window
 * with zero dispersion yields 0.
 */
class Skewness implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;
	var sumCu:Float;

	public function new(period:Int) {
		if (period < 3) throw "Skewness: period must be >= 3";
		this.period = period;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		var wasFull = window.isFull();
		var old = window.push(value);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
			sumCu -= old * old * old;
		}
		sum += value;
		sumSq += value * value;
		sumCu += value * value * value;
		if (window.length < period) return null;
		var n:Float = period;
		var mean = sum / n;
		// m2 = E[x²] − E[x]²
		var m2 = sumSq / n - mean * mean;
		if (m2 < 0.0) m2 = 0.0;
		// m3 = E[x³] − 3·mean·E[x²] + 2·mean³ (binomial expansion).
		var m3 = sumCu / n - 3.0 * mean * (sumSq / n) + 2.0 * mean * mean * mean;
		if (m2 == 0.0) {
			// A window with no dispersion has no defined shape; return 0.
			return 0.0;
		}
		return m3 / Math.pow(m2, 1.5);
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
		sumCu = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Skewness";

	public static function spec():IndicatorSpec {
		return {
			name: "skewness", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "skewness:" + series + ":" + p, series, Math.NaN,
					() -> new Skewness(p), (i, v) -> (cast i : Skewness).update(v));
			}
		};
	}
}
