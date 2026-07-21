package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Hilbert Transform Dominant Cycle Phase (`HT_DCPHASE`) — ported from
 * wickra-core's `HtDcPhase`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ht_dcphase.rs).
 *
 * Runs the same adaptive Hilbert-transform engine as `HilbertDominantCycle`
 * to recover the dominant cycle period, then measures the phase angle of that
 * cycle (in degrees) by correlating the smoothed price over one
 * dominant-cycle window against a unit phasor. From *Rocket Science for
 * Traders* (Ehlers 2001), aligned with TA-Lib's `HT_DCPHASE`. First value
 * after ~50 inputs. Series input (f64): `ht_dcphase(close)`.
 */
class HtDcPhase implements MuseIndicator<Float, Float> {
	static inline var EPSILON:Float = 2.220446049250313e-16;

	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var q1Buf:Array<Float>;
	var i1Buf:Array<Float>;
	// Longer history of the 4-bar smoothed price, used to integrate the phase
	// over one dominant-cycle window (up to 50 bars).
	var smoothPrice:Array<Float>;
	var prevI2:Float;
	var prevQ2:Float;
	var prevRe:Float;
	var prevIm:Float;
	var prevPeriod:Float;
	var prevSmoothPeriod:Float;
	var count:Int;
	var lastValue:Null<Float>;

	public function new() {
		reset();
	}

	/** Current dominant-cycle phase (degrees) if available. */
	public function value():Null<Float> return lastValue;

	static function pushFront(buf:Array<Float>, v:Float, cap:Int):Void {
		buf.unshift(v);
		if (buf.length > cap) {
			buf.splice(cap, buf.length - cap);
		}
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastValue;
		count++;

		pushFront(smoothBuf, input, 7);
		if (smoothBuf.length < 7) return null;
		var smooth = (4.0 * smoothBuf[0] + 3.0 * smoothBuf[1] + 2.0 * smoothBuf[2] + smoothBuf[3]) / 10.0;
		pushFront(smoothPrice, smooth, 50);

		var period = Math.min(Math.max(prevPeriod, 6.0), 50.0);
		var adj = 0.075 * period + 0.54;

		var s0 = smooth;
		var s2 = smoothBuf[2];
		var s4 = smoothBuf[4];
		var s6 = smoothBuf[6];
		var detrender = (0.0962 * s0 + 0.5769 * s2 - 0.5769 * s4 - 0.0962 * s6) * adj;
		pushFront(detrenderBuf, detrender, 7);
		if (detrenderBuf.length < 7) return null;

		var q1 = (0.0962 * detrenderBuf[0] + 0.5769 * detrenderBuf[2]
			- 0.5769 * detrenderBuf[4] - 0.0962 * detrenderBuf[6]) * adj;
		var i1 = detrenderBuf[3];

		pushFront(q1Buf, q1, 7);
		pushFront(i1Buf, i1, 7);
		if (q1Buf.length < 7 || i1Buf.length < 7) return null;

		var ji = (0.0962 * i1Buf[0] + 0.5769 * i1Buf[2]
			- 0.5769 * i1Buf[4] - 0.0962 * i1Buf[6]) * adj;
		var jq = (0.0962 * q1Buf[0] + 0.5769 * q1Buf[2]
			- 0.5769 * q1Buf[4] - 0.0962 * q1Buf[6]) * adj;

		var i2 = i1 - jq;
		var q2 = q1 + ji;
		i2 = 0.2 * i2 + 0.8 * prevI2;
		q2 = 0.2 * q2 + 0.8 * prevQ2;

		var re = i2 * prevI2 + q2 * prevQ2;
		var im = i2 * prevQ2 - q2 * prevI2;
		re = 0.2 * re + 0.8 * prevRe;
		im = 0.2 * im + 0.8 * prevIm;

		prevI2 = i2;
		prevQ2 = q2;
		prevRe = re;
		prevIm = im;

		var newPeriod = if (Math.abs(im) > EPSILON && Math.abs(re) > EPSILON) {
			2.0 * Math.PI / Math.atan2(im, re);
		} else {
			prevPeriod;
		};
		newPeriod = Math.min(newPeriod, 1.5 * prevPeriod);
		newPeriod = Math.max(newPeriod, 0.67 * prevPeriod);
		newPeriod = Math.min(Math.max(newPeriod, 6.0), 50.0);
		prevPeriod = 0.2 * newPeriod + 0.8 * prevPeriod;
		prevSmoothPeriod = 0.33 * prevPeriod + 0.67 * prevSmoothPeriod;

		if (count < 50) return null;

		// Integrate the smoothed price over one dominant-cycle window against a
		// unit phasor to recover the instantaneous dominant-cycle phase.
		var smoothPeriod = prevSmoothPeriod;
		var dcPeriod = Std.int(smoothPeriod + 0.5);
		if (dcPeriod < 1) dcPeriod = 1;
		if (dcPeriod > smoothPrice.length) dcPeriod = smoothPrice.length;
		var realPart = 0.0;
		var imagPart = 0.0;
		for (i in 0...dcPeriod) {
			var angle = i * 2.0 * Math.PI / dcPeriod;
			var sp = smoothPrice[i];
			realPart += Math.sin(angle) * sp;
			imagPart += Math.cos(angle) * sp;
		}

		var dcPhase = computeDcPhase(realPart, imagPart, smoothPeriod);

		lastValue = dcPhase;
		return dcPhase;
	}

	/**
	 * Recovers the dominant-cycle phase (degrees) from the real/imaginary
	 * parts of the one-cycle homodyne integration, unwrapped into TA-Lib's
	 * `[-45, 315)` output range with the 4-bar smoother group-delay
	 * correction. When `imagPart` is within `±0.001` of zero the `atan` is
	 * undefined, so the phase collapses to `±90°` by the sign of `realPart`.
	 */
	public static function computeDcPhase(realPart:Float, imagPart:Float, smoothPeriod:Float):Float {
		var dcPhase = if (Math.abs(imagPart) > 0.001) {
			Math.atan(realPart / imagPart) * 180.0 / Math.PI;
		} else if (realPart < 0.0) {
			-90.0;
		} else {
			90.0;
		};
		dcPhase += 90.0;
		// Compensate the group delay of the 4-bar weighted smoother.
		dcPhase += 360.0 / smoothPeriod;
		if (imagPart < 0.0) {
			dcPhase += 180.0;
		}
		if (dcPhase > 315.0) {
			dcPhase -= 360.0;
		}
		return dcPhase;
	}

	public function reset():Void {
		smoothBuf = [];
		detrenderBuf = [];
		q1Buf = [];
		i1Buf = [];
		smoothPrice = [];
		prevI2 = 0.0;
		prevQ2 = 0.0;
		prevRe = 0.0;
		prevIm = 0.0;
		prevPeriod = 0.0;
		prevSmoothPeriod = 0.0;
		count = 0;
		lastValue = null;
	}

	public function warmupPeriod():Int return 50;
	public function isReady():Bool return lastValue != null;
	public function name():String return "HT_DCPHASE";

	public static function spec():IndicatorSpec {
		return {
			name: "ht_dcphase", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "ht_dcphase:" + series, series, Math.NaN,
					() -> new HtDcPhase(), (i, v) -> (cast i : HtDcPhase).update(v));
			}
		};
	}
}
