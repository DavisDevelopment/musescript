package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/**
 * Ehlers Hilbert Transform Dominant Cycle period estimator — ported from
 * wickra-core's `HilbertDominantCycle`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/hilbert_dominant_cycle.rs).
 *
 * Decomposes price into in-phase and quadrature components via Ehlers'
 * truncated Hilbert transform, then derives the instantaneous phase. The
 * dominant cycle period is recovered from the phase rate of change and
 * median-smoothed. The output is clamped to the band `[6, 50]` bars.
 *
 * A `prim/` PRIMITIVE, not a builtin: reusable building block for adaptive
 * oscillators (e.g., AdaptiveCycle).
 */
class HilbertDominantCycle implements MuseIndicator<Float, Float> {
	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var q1Buf:Array<Float>;
	var i1Buf:Array<Float>;
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

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastValue;
		count++;

		// 4-bar weighted moving average of the input.
		pushFront(smoothBuf, input, 7);
		if (smoothBuf.length < 4) return null;
		var smooth = (4.0 * smoothBuf[0] + 3.0 * smoothBuf[1] + 2.0 * smoothBuf[2] + smoothBuf[3]) / 10.0;

		// Adaptive coefficient based on the previous period estimate.
		var period = Math.max(prevPeriod, 6.0);
		period = Math.min(period, 50.0);
		var adj = 0.075 * period + 0.54;

		if (smoothBuf.length < 7) return null;

		// Ehlers' Hilbert transform of `smooth`.
		var s0 = smooth;
		var s2 = smoothBuf[2];
		var s4 = smoothBuf[4];
		var s6 = smoothBuf[6];
		var detrender = (0.0962 * s0 + 0.5769 * s2 - 0.5769 * s4 - 0.0962 * s6) * adj;
		pushFront(detrenderBuf, detrender, 7);

		if (detrenderBuf.length < 7) return null;

		// In-phase and quadrature components.
		var q1 = (0.0962 * detrenderBuf[0] + 0.5769 * detrenderBuf[2] - 0.5769 * detrenderBuf[4] - 0.0962 * detrenderBuf[6]) * adj;
		var i1 = detrenderBuf[3];

		pushFront(q1Buf, q1, 7);
		pushFront(i1Buf, i1, 7);
		if (q1Buf.length < 7 || i1Buf.length < 7) return null;

		// Advance the phase 90 deg via a second Hilbert pass.
		var ji = (0.0962 * i1Buf[0] + 0.5769 * i1Buf[2] - 0.5769 * i1Buf[4] - 0.0962 * i1Buf[6]) * adj;
		var jq = (0.0962 * q1Buf[0] + 0.5769 * q1Buf[2] - 0.5769 * q1Buf[4] - 0.0962 * q1Buf[6]) * adj;

		// Phasor smoothing.
		var i2 = i1 - jq;
		var q2 = q1 + ji;
		i2 = 0.2 * i2 + 0.8 * prevI2;
		q2 = 0.2 * q2 + 0.8 * prevQ2;

		// Homodyne discriminator.
		var re = i2 * prevI2 + q2 * prevQ2;
		var im = i2 * prevQ2 - q2 * prevI2;
		re = 0.2 * re + 0.8 * prevRe;
		im = 0.2 * im + 0.8 * prevIm;

		prevI2 = i2;
		prevQ2 = q2;
		prevRe = re;
		prevIm = im;

		var newPeriod:Float;
		if (Math.abs(im) > 1e-15 && Math.abs(re) > 1e-15) {
			newPeriod = 2.0 * Math.PI / Math.atan2(im, re);
		} else {
			newPeriod = prevPeriod;
		}

		// Rate-of-change clamp per Ehlers.
		newPeriod = Math.min(newPeriod, 1.5 * prevPeriod);
		newPeriod = Math.max(newPeriod, 0.67 * prevPeriod);
		newPeriod = Math.max(newPeriod, 6.0);
		newPeriod = Math.min(newPeriod, 50.0);

		// EMA smoothing of the period.
		prevPeriod = 0.2 * newPeriod + 0.8 * prevPeriod;
		// Second smoothing step.
		prevSmoothPeriod = 0.33 * prevPeriod + 0.67 * prevSmoothPeriod;

		if (count < 50) return null;
		lastValue = prevSmoothPeriod;
		return prevSmoothPeriod;
	}

	public function reset():Void {
		smoothBuf = [];
		detrenderBuf = [];
		q1Buf = [];
		i1Buf = [];
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
	public function name():String return "HilbertDominantCycle";

	/** Latest value, or NaN before ready. */
	public function value():Float return lastValue != null ? lastValue : Math.NaN;

	static inline function pushFront(buf:Array<Float>, v:Float, cap:Int):Void {
		buf.unshift(v);
		if (buf.length > cap) {
			buf.pop();
		}
	}
}
