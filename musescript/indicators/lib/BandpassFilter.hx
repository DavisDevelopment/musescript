package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers Bandpass Filter — ported from wickra-core's `BandpassFilter`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/bandpass_filter.rs).
 *
 * A two-pole resonator that passes the cyclic content around a target `period`
 * and rejects both the trend (low frequencies) and the noise (high frequencies).
 *
 * From John Ehlers' *Cycle Analytics for Traders* (2013):
 *
 * ```text
 * beta  = cos(2π / period)
 * gamma = 1 / cos(4π · bandwidth / period)
 * alpha = gamma − sqrt(gamma² − 1)
 * BP_t  = 0.5·(1 − alpha)·(price_t − price_{t−2})
 *         + beta·(1 + alpha)·BP_{t−1} − alpha·BP_{t−2}
 * ```
 *
 * `bandwidth` (a fraction, typically `0.3`) sets how wide a band of periods is
 * admitted: narrow bandwidth gives a sharp, ringing resonator tuned tightly to
 * `period`; wide bandwidth lets more of the spectrum through. The output is a
 * zero-mean oscillator — it swings symmetrically around `0`, peaking when the
 * dominant cycle aligns with `period`. The recursion needs two prior prices
 * and two prior outputs; until then it emits `0`, so a value is produced
 * every bar.
 */
class BandpassFilter implements MuseIndicator<Float, Float> {
	var period:Int;
	var bandwidth:Float;
	var beta:Float;
	var alpha:Float;
	var prevPrice1:Null<Float>;
	var prevPrice2:Null<Float>;
	var bp1:Float;
	var bp2:Float;
	var last:Null<Float>;

	public function new(period:Int, bandwidth:Float) {
		if (period <= 0) throw "BandpassFilter: period must be > 0";
		if (!Math.isFinite(bandwidth) || bandwidth <= 0.0 || bandwidth >= 1.0) {
			throw "BandpassFilter: bandwidth must be in (0, 1)";
		}
		this.period = period;
		this.bandwidth = bandwidth;
		var periodF = period;
		var pi2 = Math.PI * 2.0;
		beta = Math.cos(pi2 / periodF);
		var gamma = 1.0 / Math.cos((4.0 * Math.PI * bandwidth) / periodF);
		alpha = gamma - Math.sqrt(gamma * gamma - 1.0);
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return last;
		var bp = if (prevPrice2 != null) {
			0.5 * (1.0 - alpha) * (price - prevPrice2) + beta * (1.0 + alpha) * bp1 - alpha * bp2;
		} else {
			0.0;
		};
		prevPrice2 = prevPrice1;
		prevPrice1 = price;
		bp2 = bp1;
		bp1 = bp;
		last = bp;
		return bp;
	}

	public function reset():Void {
		prevPrice1 = null;
		prevPrice2 = null;
		bp1 = 0.0;
		bp2 = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return last != null;
	public function name():String return "BandpassFilter";

	public static function spec():IndicatorSpec {
		return {
			name: "bandpass_filter", args: [TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var bw = IndicatorCache.floatArg(args, 1, 0.3);
				return IndicatorCache.evalSeries(h, "bandpass_filter:" + p + ":" + bw, "close", Math.NaN,
					() -> new BandpassFilter(p, bw), (i, v) -> (cast i : BandpassFilter).update(v));
			}
		};
	}
}
