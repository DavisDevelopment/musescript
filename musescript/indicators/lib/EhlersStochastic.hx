package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.RoofingFilter;
import musescript.types.MuseType;

/**
 * Ehlers Stochastic — ported from wickra-core's `EhlersStochastic`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ehlers_stochastic.rs).
 *
 * Implements the construction from *Cycle Analytics for Traders* (Ehlers 2013, ch. 7):
 * the raw price is first passed through a RoofingFilter (high-pass + SuperSmoother
 * bandpass) to isolate the tradable cycle band, then the classic Stochastic %K
 * formula is applied to the filtered output over `period` bars and finally re-smoothed
 * by a 2-bar SMA. The result is a ±1-normalized oscillator that reacts to cycles
 * without trending bias from low-frequency drift.
 *
 * Output range is [-1, +1] rather than the conventional [0, 100].
 */
class EhlersStochastic implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	var roofing:RoofingFilter;
	var filteredBuf:Array<Float>;
	var prevStoch:Float;
	var hasPrev:Bool;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "EhlersStochastic: period must be > 0";
		this.period = period;
		// Defaults match Ehlers' (10, 48) roofing filter cutoffs.
		roofing = new RoofingFilter(10, 48);
		filteredBuf = [];
		prevStoch = 0.0;
		hasPrev = false;
		lastValue = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return lastValue;
		}

		var filtered = roofing.update(input);
		if (filtered == null) {
			return null;
		}

		if (filteredBuf.length == period) {
			filteredBuf.shift();
		}
		filteredBuf.push(filtered);

		if (filteredBuf.length < period) {
			return null;
		}

		// Find max and min in the filtered buffer
		var max = Math.NEGATIVE_INFINITY;
		var min = Math.POSITIVE_INFINITY;
		for (v in filteredBuf) {
			if (v > max) max = v;
			if (v < min) min = v;
		}

		var range = max - min;
		var raw = if (range > 0.0) {
			((filtered - min) / range) * 2.0 - 1.0;
		} else {
			0.0;
		}

		// 2-bar SMA smoothing
		var smoothed = if (hasPrev) {
			0.5 * (raw + prevStoch);
		} else {
			raw;
		}

		prevStoch = raw;
		hasPrev = true;
		lastValue = smoothed;

		return smoothed;
	}

	public function reset():Void {
		roofing.reset();
		filteredBuf = [];
		prevStoch = 0.0;
		hasPrev = false;
		lastValue = null;
	}

	public function warmupPeriod():Int return period + roofing.warmupPeriod();
	public function isReady():Bool return lastValue != null;
	public function name():String return "EhlersStochastic";

	public static function spec():IndicatorSpec {
		return {
			name: "ehlers_stochastic", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "ehlers_stochastic:" + series + ":" + p, series, Math.NaN,
					() -> new EhlersStochastic(p), (i, v) -> (cast i : EhlersStochastic).update(v));
			}
		};
	}
}
