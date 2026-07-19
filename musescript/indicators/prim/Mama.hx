package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;

/** MAMA + FAMA output pair. */
typedef MamaOutput = {
	var mama:Float;
	var fama:Float;
}

/**
 * MESA Adaptive Moving Average (MAMA) — ported from wickra-core's `Mama`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/mama.rs).
 *
 * MAMA adapts its smoothing constant from the rate-of-change of price phase,
 * derived via a truncated Hilbert transform. See "Cycle Analytics for Traders"
 * (Ehlers 2013, ch. 8) for the full mathematical treatment.
 *
 * The two-parameter (fast_limit, slow_limit) is the range over which the
 * adaptive alpha can vary; defaults (0.5, 0.05) match the canonical implementation.
 * FAMA is a lagging companion line that confirms trends.
 *
 * A `prim/` PRIMITIVE, not a builtin. Reusable building block for Fama and other
 * indicators. Not registered as a builtin.
 */
class Mama implements MuseIndicator<Float, MamaOutput> {
	var fastLimit:Float;
	var slowLimit:Float;
	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var q1Buf:Array<Float>;
	var i1Buf:Array<Float>;
	var prevI2:Float;
	var prevQ2:Float;
	var prevRe:Float;
	var prevIm:Float;
	var prevPeriod:Float;
	var prevPhase:Float;
	var prevMama:Float;
	var prevFama:Float;
	var count:Int;
	var lastValue:Null<MamaOutput>;

	public function new(fastLimit:Float, slowLimit:Float) {
		if (!Math.isFinite(fastLimit) || !Math.isFinite(slowLimit) ||
			fastLimit <= 0.0 || fastLimit > 1.0 ||
			slowLimit <= 0.0 || slowLimit > 1.0 ||
			slowLimit > fastLimit) {
			throw "Mama: fast_limit, slow_limit must satisfy 0 < slow_limit <= fast_limit <= 1";
		}
		this.fastLimit = fastLimit;
		this.slowLimit = slowLimit;
		smoothBuf = [];
		detrenderBuf = [];
		q1Buf = [];
		i1Buf = [];
		prevI2 = 0.0;
		prevQ2 = 0.0;
		prevRe = 0.0;
		prevIm = 0.0;
		prevPeriod = 0.0;
		prevPhase = 0.0;
		prevMama = 0.0;
		prevFama = 0.0;
		count = 0;
		lastValue = null;
	}

	static function pushFront(buf:Array<Float>, v:Float, cap:Int):Void {
		buf.unshift(v);
		if (buf.length > cap) {
			buf.splice(cap, buf.length - cap);
		}
	}

	public function update(input:Float):Null<MamaOutput> {
		if (!Math.isFinite(input)) return lastValue;
		count++;

		pushFront(smoothBuf, input, 7);
		if (smoothBuf.length < 4) {
			return null;
		}

		var smooth = (4.0 * smoothBuf[0] + 3.0 * smoothBuf[1] + 2.0 * smoothBuf[2] + smoothBuf[3]) / 10.0;

		var period = Math.max(prevPeriod, 6.0);
		period = Math.min(period, 50.0);
		var adj = 0.075 * period + 0.54;

		if (smoothBuf.length < 7) {
			// Seed the EMA outputs with the smoothed price
			prevMama = smooth;
			prevFama = smooth;
			return null;
		}

		var s0 = smooth;
		var s2 = smoothBuf[2];
		var s4 = smoothBuf[4];
		var s6 = smoothBuf[6];
		var detrender = (0.0962 * s0 + 0.5769 * s2 - 0.5769 * s4 - 0.0962 * s6) * adj;
		pushFront(detrenderBuf, detrender, 7);
		if (detrenderBuf.length < 7) {
			return null;
		}

		var q1 = (0.0962 * detrenderBuf[0] + 0.5769 * detrenderBuf[2]
			- 0.5769 * detrenderBuf[4] - 0.0962 * detrenderBuf[6]) * adj;
		var i1 = detrenderBuf[3];
		pushFront(q1Buf, q1, 7);
		pushFront(i1Buf, i1, 7);
		if (q1Buf.length < 7 || i1Buf.length < 7) {
			return null;
		}

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

		var newPeriod = if (Math.abs(im) > 1e-10 && Math.abs(re) > 1e-10) {
			2.0 * Math.PI / Math.atan2(im, re);
		} else {
			prevPeriod;
		};
		newPeriod = Math.min(newPeriod, 1.5 * prevPeriod);
		newPeriod = Math.max(newPeriod, 0.67 * prevPeriod);
		newPeriod = Math.max(6.0, Math.min(50.0, newPeriod));
		prevPeriod = 0.2 * newPeriod + 0.8 * prevPeriod;

		var phase = if (Math.abs(i1) > 1e-10) {
			Math.atan(q1 / i1) * 180.0 / Math.PI;
		} else {
			prevPhase;
		};
		var deltaPhase = prevPhase - phase;
		prevPhase = phase;
		if (deltaPhase < 1.0) {
			deltaPhase = 1.0;
		}
		var alpha = fastLimit / deltaPhase;
		if (alpha < slowLimit) {
			alpha = slowLimit;
		}

		prevMama = alpha * input + (1.0 - alpha) * prevMama;
		var famaAlpha = 0.5 * alpha;
		prevFama = famaAlpha * prevMama + (1.0 - famaAlpha) * prevFama;

		if (count < 33) {
			return null;
		}

		var out = { mama: prevMama, fama: prevFama };
		lastValue = out;
		return out;
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
		prevPhase = 0.0;
		prevMama = 0.0;
		prevFama = 0.0;
		count = 0;
		lastValue = null;
	}

	public function warmupPeriod():Int return 33;
	public function isReady():Bool return lastValue != null;
	public function name():String return "MAMA";

	/** Current (mama, fama) pair if available. */
	public function value():Null<MamaOutput> return lastValue;
}
