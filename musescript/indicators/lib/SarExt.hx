package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Parabolic SAR Extended (SAREXT) — ported from wickra-core's `SarExt`
 * (vendor/wickra/crates/wickra-core/src/indicators/sar_ext.rs).
 *
 * Wilder's Parabolic SAR with TA-Lib's extended controls: a `startValue`
 * (0 auto-seeds long like PSAR, positive starts a long phase at that SAR,
 * negative starts a short phase at its absolute value), an
 * `offsetOnReverse` fractional offset pushing the reversal SAR further from
 * price, and separate long/short (init, step, max) acceleration schedules.
 *
 * The output is SIGNED: positive during a long phase (SAR below price),
 * negative during a short phase (SAR above price).
 */
class SarExt implements MuseIndicator<Bar, Float> {
	var startValue:Float;
	var offsetOnReverse:Float;
	var longInit:Float;
	var longStep:Float;
	var longMax:Float;
	var shortInit:Float;
	var shortStep:Float;
	var shortMax:Float;

	var initialised:Bool;
	var hasEmitted:Bool;
	var prevHigh:Float;
	var prevLow:Float;
	/** true = uptrend, false = downtrend. */
	var trendUp:Bool;
	var sar:Float;
	var ep:Float;
	var af:Float;

	public function new(startValue:Float, offsetOnReverse:Float,
			accelInitLong:Float, accelLong:Float, accelMaxLong:Float,
			accelInitShort:Float, accelShort:Float, accelMaxShort:Float) {
		if (!Math.isFinite(startValue) || !Math.isFinite(offsetOnReverse) || offsetOnReverse < 0.0)
			throw "SarExt: start_value and offset_on_reverse must be finite, offset must be >= 0";
		validateAccel(accelInitLong, accelLong, accelMaxLong);
		validateAccel(accelInitShort, accelShort, accelMaxShort);
		this.startValue = startValue;
		this.offsetOnReverse = offsetOnReverse;
		longInit = accelInitLong;
		longStep = accelLong;
		longMax = accelMaxLong;
		shortInit = accelInitShort;
		shortStep = accelShort;
		shortMax = accelMaxShort;
		reset();
	}

	static function validateAccel(init:Float, step:Float, max:Float):Void {
		if (!(Math.isFinite(init) && Math.isFinite(step) && Math.isFinite(max)))
			throw "SarExt: acceleration terms must be positive and finite";
		if (init <= 0.0 || step <= 0.0 || max <= 0.0)
			throw "SarExt: acceleration terms must be positive and finite";
		if (init > max)
			throw "SarExt: acceleration init must be <= max";
	}

	/** Wilder's defaults: no start value or reversal offset, symmetric (0.02, 0.02, 0.20). */
	public static function classic():SarExt {
		return new SarExt(0.0, 0.0, 0.02, 0.02, 0.20, 0.02, 0.02, 0.20);
	}

	inline function signed(sarVal:Float):Float {
		return trendUp ? sarVal : -sarVal;
	}

	public function update(bar:Bar):Null<Float> {
		if (!initialised) {
			prevHigh = bar.high;
			prevLow = bar.low;
			if (startValue > 0.0) {
				trendUp = true;
				sar = startValue;
				ep = bar.high;
				af = longInit;
			} else if (startValue < 0.0) {
				trendUp = false;
				sar = -startValue;
				ep = bar.low;
				af = shortInit;
			} else {
				trendUp = true;
				sar = bar.low;
				ep = bar.high;
				af = longInit;
			}
			initialised = true;
			return null;
		}

		var newSar = sar + af * (ep - sar);
		if (trendUp) {
			newSar = Math.min(Math.min(newSar, prevLow), bar.low);
		} else {
			newSar = Math.max(Math.max(newSar, prevHigh), bar.high);
		}

		var outputSar = newSar;
		var reversed = trendUp ? bar.low <= newSar : bar.high >= newSar;

		if (reversed) {
			outputSar = ep;
			trendUp = !trendUp;
			if (trendUp) {
				outputSar -= Math.abs(outputSar) * offsetOnReverse;
				ep = bar.high;
				af = longInit;
			} else {
				outputSar += Math.abs(outputSar) * offsetOnReverse;
				ep = bar.low;
				af = shortInit;
			}
		} else {
			if (trendUp) {
				if (bar.high > ep) {
					ep = bar.high;
					af = Math.min(af + longStep, longMax);
				}
			} else {
				if (bar.low < ep) {
					ep = bar.low;
					af = Math.min(af + shortStep, shortMax);
				}
			}
		}

		sar = outputSar;
		prevHigh = bar.high;
		prevLow = bar.low;
		hasEmitted = true;
		return signed(outputSar);
	}

	public function reset():Void {
		initialised = false;
		hasEmitted = false;
		prevHigh = Math.NaN;
		prevLow = Math.NaN;
		trendUp = true;
		sar = Math.NaN;
		ep = Math.NaN;
		af = longInit;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "SAREXT";

	public static function spec():IndicatorSpec {
		return {
			name: "sar_ext",
			args: [TScalar, TScalar, TScalar, TScalar, TScalar, TScalar, TScalar, TScalar],
			ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var sv = IndicatorCache.floatArg(args, 0, 0.0);
				var off = IndicatorCache.floatArg(args, 1, 0.0);
				var il = IndicatorCache.floatArg(args, 2, 0.02);
				var sl = IndicatorCache.floatArg(args, 3, 0.02);
				var ml = IndicatorCache.floatArg(args, 4, 0.20);
				var is_ = IndicatorCache.floatArg(args, 5, 0.02);
				var ss = IndicatorCache.floatArg(args, 6, 0.02);
				var ms = IndicatorCache.floatArg(args, 7, 0.20);
				var key = "sar_ext:" + sv + ":" + off + ":" + il + ":" + sl + ":" + ml + ":" + is_ + ":" + ss + ":" + ms;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new SarExt(sv, off, il, sl, ml, is_, ss, ms),
					(i, b) -> (cast i : SarExt).update(b));
			}
		};
	}
}
