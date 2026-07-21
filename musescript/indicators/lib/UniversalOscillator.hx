package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.SuperSmoother;
import musescript.types.MuseType;

/**
 * Ehlers' Universal Oscillator — ported from wickra-core's
 * `UniversalOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/universal_oscillator.rs).
 *
 * From *Cycle Analytics for Traders* (Ehlers 2013): whitens the price series
 * (two-bar difference `(price_t − price_{t−2}) / 2`), SuperSmooths it, then
 * normalises with an automatic gain control (decaying peak
 * `max(|filt|, 0.991·peak)`) so the output swings in `[−1, +1]`. First value
 * once a two-bar difference exists (`warmupPeriod == 3`).
 * Series input (f64): `universal_oscillator(close, period)`.
 */
class UniversalOscillator implements MuseIndicator<Float, Float> {
	var period:Int;
	var smoother:SuperSmoother;
	var prevPrice1:Null<Float>;
	var prevPrice2:Null<Float>;
	var peak:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "UniversalOscillator: period must be > 0";
		this.period = period;
		smoother = new SuperSmoother(period);
		prevPrice1 = null;
		prevPrice2 = null;
		peak = 0.0;
		last = null;
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Current value if available. */
	public function value():Null<Float> return last;

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return last;
		if (prevPrice2 == null) {
			prevPrice2 = prevPrice1;
			prevPrice1 = price;
			return null;
		}
		var p2:Float = prevPrice2;
		var whiteNoise = (price - p2) / 2.0;
		if (!Math.isFinite(whiteNoise)) {
			// `price - p2` can overflow to +/-inf even when both are finite;
			// skip the bar rather than feeding a non-finite value downstream.
			prevPrice2 = prevPrice1;
			prevPrice1 = price;
			return last;
		}
		// SuperSmoother emits from the first input, so this is never null here.
		var filt:Float = smoother.update(whiteNoise);
		peak = Math.max(Math.abs(filt), 0.991 * peak);
		var universal = if (peak > 0.0) {
			Math.min(Math.max(filt / peak, -1.0), 1.0);
		} else {
			0.0;
		};
		prevPrice2 = prevPrice1;
		prevPrice1 = price;
		last = universal;
		return universal;
	}

	public function reset():Void {
		smoother.reset();
		prevPrice1 = null;
		prevPrice2 = null;
		peak = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return last != null;
	public function name():String return "UniversalOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "universal_oscillator", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "universal_oscillator:" + series + ":" + p, series, Math.NaN,
					() -> new UniversalOscillator(p), (i, v) -> (cast i : UniversalOscillator).update(v));
			}
		};
	}
}
