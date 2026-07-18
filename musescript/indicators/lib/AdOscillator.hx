package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Williams A/D Oscillator (ADOSC) — ported from wickra-core's `AdOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ad_oscillator.rs).
 *
 * The volume-free Williams Accumulation/Distribution line measured against its
 * own moving average, oscillating around zero.
 *
 * TR_h_t = max(close_{t−1}, high_t)
 * TR_l_t = min(close_{t−1}, low_t)
 * WAD_t  = WAD_{t−1} + (close_t − TR_l_t)   if close_t > close_{t−1}
 * WAD_t  = WAD_{t−1} + (close_t − TR_h_t)   if close_t < close_{t−1}
 * WAD_t  = WAD_{t−1}                          if close_t == close_{t−1}
 * ADOSC_t = WAD_t − SMA(WAD, 13)_t
 */
class AdOscillator implements MuseIndicator<Bar, Float> {
	static inline var SIGNAL_PERIOD = 13;

	var prevClose:Null<Float>;
	var line:Float;
	var signal:Sma;
	var last:Null<Float>;

	public function new() {
		prevClose = null;
		line = 0.0;
		signal = new Sma(SIGNAL_PERIOD);
		last = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			// The first bar only establishes the previous close anchor.
			prevClose = bar.close;
			return null;
		}
		var delta = if (bar.close > prevClose) {
			// Accumulation: distance from the true low.
			bar.close - Math.min(prevClose, bar.low);
		} else if (bar.close < prevClose) {
			// Distribution: distance from the true high (negative).
			bar.close - Math.max(prevClose, bar.high);
		} else {
			0.0;
		}
		line += delta;
		prevClose = bar.close;
		var signalVal = signal.update(line);
		if (signalVal == null) return null;
		var osc = line - signalVal;
		last = osc;
		return osc;
	}

	public function reset():Void {
		prevClose = null;
		line = 0.0;
		signal.reset();
		last = null;
	}

	public function warmupPeriod():Int return 1 + SIGNAL_PERIOD;
	public function isReady():Bool return last != null;
	public function name():String return "ADOSC";

	public static function spec():IndicatorSpec {
		return {
			name: "ad_oscillator", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "ad_oscillator", Math.NaN,
					() -> new AdOscillator(), (i, b) -> (cast i : AdOscillator).update(b));
			}
		};
	}
}
