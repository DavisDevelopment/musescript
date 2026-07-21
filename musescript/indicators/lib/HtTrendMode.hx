package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Hilbert Transform Trend Mode (`HT_TRENDMODE`) — ported from
 * wickra-core's `HtTrendMode`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ht_trendmode.rs).
 *
 * Runs the same adaptive Hilbert-transform engine as `HilbertDominantCycle`,
 * derives the dominant cycle phase, its sine / lead-sine, and an
 * instantaneous trendline, then classifies the market into trend mode (`1`)
 * or cycle mode (`0`). From *Rocket Science for Traders* (Ehlers 2001),
 * aligned with TA-Lib's `HT_TRENDMODE`. First value after ~50 inputs.
 * Series input (f64): `ht_trendmode(close)`.
 */
class HtTrendMode implements MuseIndicator<Float, Float> {
	static inline var EPSILON:Float = 2.220446049250313e-16;

	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var q1Buf:Array<Float>;
	var i1Buf:Array<Float>;
	var smoothPrice:Array<Float>;
	var prevI2:Float;
	var prevQ2:Float;
	var prevRe:Float;
	var prevIm:Float;
	var prevPeriod:Float;
	var prevSmoothPeriod:Float;
	// Trend-mode state.
	var prevDcPhase:Float;
	var prevSine:Float;
	var prevLeadSine:Float;
	var daysInTrend:Float;
	var it1:Float;
	var it2:Float;
	var it3:Float;
	var count:Int;
	var lastValue:Null<Float>;

	public function new() {
		reset();
	}

	/** Current trend-mode flag (`1.0` trend, `0.0` cycle) if available. */
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

		var smoothPeriod = prevSmoothPeriod;
		var dcPeriod = Std.int(smoothPeriod + 0.5);
		if (dcPeriod < 1) dcPeriod = 1;
		if (dcPeriod > smoothPrice.length) dcPeriod = smoothPrice.length;

		// Dominant-cycle phase over one cycle window.
		var realPart = 0.0;
		var imagPart = 0.0;
		for (i in 0...dcPeriod) {
			var angle = i * 2.0 * Math.PI / dcPeriod;
			var sp = smoothPrice[i];
			realPart += Math.sin(angle) * sp;
			imagPart += Math.cos(angle) * sp;
		}
		var dcPhase = HtDcPhase.computeDcPhase(realPart, imagPart, smoothPeriod);

		var sine = Math.sin(dcPhase * Math.PI / 180.0);
		var leadSine = Math.sin((dcPhase + 45.0) * Math.PI / 180.0);

		// Instantaneous trendline: average smoothed price over the cycle window,
		// then a 4-3-2-1 weighted smoothing of that running average.
		var trendSum = 0.0;
		for (i in 0...dcPeriod) {
			trendSum += smoothPrice[i];
		}
		trendSum /= dcPeriod;
		var trendline = (4.0 * trendSum + 3.0 * it1 + 2.0 * it2 + it3) / 10.0;
		it3 = it2;
		it2 = it1;
		it1 = trendSum;

		// Trend / cycle decision (assume trend, override to cycle).
		var trend = 1.0;

		// A crossing of sine and lead-sine restarts the cycle clock.
		if ((sine > leadSine && prevSine <= prevLeadSine)
			|| (sine < leadSine && prevSine >= prevLeadSine)) {
			daysInTrend = 0.0;
			trend = 0.0;
		}
		daysInTrend += 1.0;
		if (daysInTrend < 0.5 * smoothPeriod) {
			trend = 0.0;
		}

		// Cycle mode while the phase advances at roughly the dominant-cycle rate.
		var deltaPhase = dcPhase - prevDcPhase;
		if (smoothPeriod != 0.0
			&& deltaPhase > 0.67 * 360.0 / smoothPeriod
			&& deltaPhase < 1.5 * 360.0 / smoothPeriod) {
			trend = 0.0;
		}

		// Force trend mode when price separates from the trendline.
		if (trendline != 0.0 && Math.abs((smooth - trendline) / trendline) >= 0.015) {
			trend = 1.0;
		}

		prevDcPhase = dcPhase;
		prevSine = sine;
		prevLeadSine = leadSine;

		if (count < 50) return null;
		lastValue = trend;
		return trend;
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
		prevDcPhase = 0.0;
		prevSine = 0.0;
		prevLeadSine = 0.0;
		daysInTrend = 0.0;
		it1 = 0.0;
		it2 = 0.0;
		it3 = 0.0;
		count = 0;
		lastValue = null;
	}

	public function warmupPeriod():Int return 50;
	public function isReady():Bool return lastValue != null;
	public function name():String return "HT_TRENDMODE";

	public static function spec():IndicatorSpec {
		return {
			name: "ht_trendmode", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "ht_trendmode:" + series, series, Math.NaN,
					() -> new HtTrendMode(), (i, v) -> (cast i : HtTrendMode).update(v));
			}
		};
	}
}
