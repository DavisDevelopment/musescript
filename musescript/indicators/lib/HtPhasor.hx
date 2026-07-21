package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** In-phase and quadrature components of the Hilbert transform phasor. */
typedef HtPhasorOutput = {
	var inphase:Float;
	var quadrature:Float;
}

/**
 * Ehlers' Hilbert Transform Phasor (`HT_PHASOR`) — ported from wickra-core's
 * `HtPhasor`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ht_phasor.rs).
 *
 * Runs the same adaptive Hilbert-transform engine as `HilbertDominantCycle`
 * but reports the raw in-phase (`I1`) and quadrature (`Q1`) components of the
 * analytic signal rather than the recovered cycle period. From *Rocket
 * Science for Traders* (Ehlers 2001), aligned with TA-Lib's `HT_PHASOR`.
 * Series input (f64): `ht_phasor(close)`.
 */
class HtPhasor implements MuseIndicator<Float, HtPhasorOutput> {
	static inline var EPSILON:Float = 2.220446049250313e-16;

	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var q1Buf:Array<Float>;
	var i1Buf:Array<Float>;
	var prevI2:Float;
	var prevQ2:Float;
	var prevRe:Float;
	var prevIm:Float;
	var prevPeriod:Float;
	var ready:Bool;

	public function new() {
		reset();
	}

	static function pushFront(buf:Array<Float>, v:Float, cap:Int):Void {
		buf.unshift(v);
		if (buf.length > cap) {
			buf.splice(cap, buf.length - cap);
		}
	}

	public function update(input:Float):Null<HtPhasorOutput> {
		// A non-finite input is skipped and produces no value (matches Rust).
		if (!Math.isFinite(input)) return null;

		pushFront(smoothBuf, input, 7);
		if (smoothBuf.length < 7) return null;
		var smooth = (4.0 * smoothBuf[0] + 3.0 * smoothBuf[1] + 2.0 * smoothBuf[2] + smoothBuf[3]) / 10.0;

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

		// Continue the dominant-cycle period adaptation so the next bar's `adj`
		// coefficient tracks the cycle, exactly as TA-Lib's HT_PHASOR does.
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

		ready = true;
		return { inphase: i1, quadrature: q1 };
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
		ready = false;
	}

	public function warmupPeriod():Int return 19;
	public function isReady():Bool return ready;
	public function name():String return "HT_PHASOR";

	public static function spec():IndicatorSpec {
		return {
			name: "ht_phasor", args: [TSeries], ret: TObject([
				{name: "inphase", ty: TScalar}, {name: "quadrature", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var nanFill = { inphase: Math.NaN, quadrature: Math.NaN };
				return IndicatorCache.evalSeries(h, "ht_phasor:" + series, series, nanFill,
					() -> new HtPhasor(), (i, v) -> (cast i : HtPhasor).update(v));
			}
		};
	}
}
