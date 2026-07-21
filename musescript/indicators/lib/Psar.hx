package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Parabolic Stop And Reverse (Wilder) — ported from wickra-core's `Psar`
 * (vendor/wickra/crates/wickra-core/src/indicators/psar.rs).
 *
 * Wilder's original recursion: each step computes a new SAR from the previous
 * SAR, extreme point (EP) and acceleration factor (AF); the trend flips when
 * price crosses the SAR. The first candle seeds the state (assumed uptrend)
 * and returns null; the first SAR is emitted on the second candle. The SAR
 * may not penetrate today's or yesterday's range.
 */
class Psar implements MuseIndicator<Bar, Float> {
	var afStart:Float;
	var afStep:Float;
	var afMax:Float;

	var initialised:Bool;
	var hasEmitted:Bool;
	var prevHigh:Float;
	var prevLow:Float;
	/** true = uptrend, false = downtrend. */
	var trendUp:Bool;
	var sar:Float;
	var ep:Float;
	var af:Float;

	public function new(afStart:Float, afStep:Float, afMax:Float) {
		if (!Math.isFinite(afStart) || !Math.isFinite(afStep) || !Math.isFinite(afMax))
			throw "Psar: acceleration factors must be positive and finite";
		if (afStart <= 0.0 || afStep <= 0.0 || afMax <= 0.0)
			throw "Psar: acceleration factors must be positive and finite";
		if (afStart > afMax)
			throw "Psar: af_start must be <= af_max";
		this.afStart = afStart;
		this.afStep = afStep;
		this.afMax = afMax;
		reset();
	}

	/** Wilder's defaults: (0.02, 0.02, 0.20). */
	public static function classic():Psar {
		return new Psar(0.02, 0.02, 0.20);
	}

	public function update(bar:Bar):Null<Float> {
		if (!initialised) {
			// Seed on the first candle; the first SAR is emitted on the second.
			prevHigh = bar.high;
			prevLow = bar.low;
			sar = bar.low;
			ep = bar.high;
			trendUp = true;
			af = afStart;
			initialised = true;
			return null;
		}

		// Predicted SAR for this period (before clamping to prior two extremes).
		var newSar = sar + af * (ep - sar);

		// Wilder rule: SAR cannot penetrate today's or yesterday's range.
		if (trendUp) {
			newSar = Math.min(Math.min(newSar, prevLow), bar.low);
		} else {
			newSar = Math.max(Math.max(newSar, prevHigh), bar.high);
		}

		var outputSar = newSar;

		// Check for trend reversal.
		var reversed = trendUp ? bar.low <= newSar : bar.high >= newSar;

		if (reversed) {
			// Flip trend, reset AF and EP, place SAR at prior EP.
			outputSar = ep;
			trendUp = !trendUp;
			ep = trendUp ? bar.high : bar.low;
			af = afStart;
		} else {
			// Update EP and AF if a new extreme has been reached.
			if (trendUp) {
				if (bar.high > ep) {
					ep = bar.high;
					af = Math.min(af + afStep, afMax);
				}
			} else {
				if (bar.low < ep) {
					ep = bar.low;
					af = Math.min(af + afStep, afMax);
				}
			}
		}

		sar = outputSar;
		prevHigh = bar.high;
		prevLow = bar.low;
		hasEmitted = true;
		return outputSar;
	}

	public function reset():Void {
		initialised = false;
		hasEmitted = false;
		prevHigh = Math.NaN;
		prevLow = Math.NaN;
		trendUp = true;
		sar = Math.NaN;
		ep = Math.NaN;
		af = afStart;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "PSAR";

	public static function spec():IndicatorSpec {
		return {
			name: "psar", args: [TScalar, TScalar, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var afStart = IndicatorCache.floatArg(args, 0, 0.02);
				var afStep = IndicatorCache.floatArg(args, 1, 0.02);
				var afMax = IndicatorCache.floatArg(args, 2, 0.20);
				var key = "psar:" + afStart + ":" + afStep + ":" + afMax;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new Psar(afStart, afStep, afMax), (i, b) -> (cast i : Psar).update(b));
			}
		};
	}
}
