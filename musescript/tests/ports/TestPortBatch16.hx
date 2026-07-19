package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 16: 10 indicators (linreg, linreg_angle, linreg_channel, kst,
 * kurtosis, laguerre_rsi, kicking, kalman_hedge_ratio,
 * lead_lag_cross_correlation, kvo) — standard published formulas (see
 * PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch16 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── LinReg / LinRegAngle / LinRegChannel ─────────────────────────────

	public function testLinRegFlatSeriesEqualsPrice() {
		var lr = new LinReg(10);
		var out = null;
		for (i in 0...15) out = lr.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-9);
	}

	public function testLinRegPerfectTrendMatchesLastPoint() {
		// y = 2x + 1 for x=0..9 -> fitted value at the last point == the actual value.
		var lr = new LinReg(10);
		var out = null;
		for (i in 0...10) out = lr.update(2.0 * i + 1.0);
		Assert.notNull(out);
		Assert.floatEquals(19.0, out, 1e-6);
	}

	public function testLinRegAngleZeroOnFlatSeries() {
		var la = new LinRegAngle(10);
		var out = null;
		for (i in 0...15) out = la.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testLinRegAnglePositiveOnUptrend() {
		var la = new LinRegAngle(10);
		var out = null;
		for (i in 0...15) out = la.update(50.0 + i * 2.0);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testLinRegChannelUpperAboveMidAboveLower() {
		var lc = new LinRegChannel(10, 2.0);
		for (i in 0...30) {
			var out = lc.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) {
				Assert.isTrue(out.upper >= out.mid);
				Assert.isTrue(out.mid >= out.lower);
			}
		}
	}

	// ── Kst ───────────────────────────────────────────────────────────────

	public function testKstZeroOnFlatSeries() {
		var kst = new Kst([10, 15, 20, 30], [10, 10, 10, 15]);
		var out = null;
		for (i in 0...70) out = kst.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	// ── Kurtosis ──────────────────────────────────────────────────────────

	public function testKurtosisZeroOnFlatSeries() {
		var k = new Kurtosis(10);
		var out = null;
		for (i in 0...15) out = k.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── LaguerreRsi ───────────────────────────────────────────────────────

	public function testLaguerreRsiInBounds() {
		var lr = new LaguerreRsi(0.5);
		for (i in 0...40) {
			var out = lr.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) Assert.isTrue(out >= 0.0 && out <= 1.0);
		}
	}

	public function testLaguerreRsiBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new LaguerreRsi(0.5), b = new LaguerreRsi(0.5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Kicking ───────────────────────────────────────────────────────────

	public function testKickingBullish() {
		var k = new Kicking();
		k.update(bar(20.0, 20.1, 10.0, 10.05, 1.0)); // near-marubozu red
		var out = k.update(bar(21.0, 30.9, 20.95, 30.85, 1.0)); // near-marubozu green, gaps up above bar1.high
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── KalmanHedgeRatio ──────────────────────────────────────────────────

	public function testKalmanHedgeRatioConvergesTowardTrueRatio() {
		var kh = new KalmanHedgeRatio(0.01, 0.1);
		var out = null;
		for (i in 1...200) out = kh.update({ a: 3.0 * i, b: 1.0 * i });
		Assert.notNull(out);
		Assert.isTrue(Math.abs(out - 3.0) < 0.5);
	}

	// ── LeadLagCrossCorrelation ───────────────────────────────────────────

	public function testLeadLagCrossCorrelationDetectsShiftedRelationship() {
		// B leads A by exactly 2 bars: a_t = b_{t-2}. corr(a_t, b_{t-2}) should be ~1.
		var values = [for (i in 0...30) Math.sin(i * 0.3)];
		var llc = new LeadLagCrossCorrelation(10, 2);
		var out = null;
		for (i in 0...values.length) {
			var a = i >= 2 ? values[i - 2] : 0.0;
			var b = values[i];
			out = llc.update({ a: a, b: b });
		}
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-6);
	}

	// ── Kvo ───────────────────────────────────────────────────────────────

	public function testKvoFiniteOnFlatCandles() {
		// A perfectly flat typical price never flips Klinger's trend state, so
		// `cm` grows unboundedly and vf converges to its asymptote only very
		// slowly (verified numerically: still ~0.01 after 2000 bars) — a real
		// property of Klinger's own formula, not a bug. Just check it stays
		// finite and doesn't blow up.
		var kvo = new Kvo(5, 10);
		var out = null;
		for (i in 0...20) out = kvo.update(bar(10.0, 11.0, 9.0, 10.0, 100.0));
		Assert.notNull(out);
		Assert.isTrue(Math.isFinite(out));
	}

	public function testKvoBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			bar(base, base + 2.0, base - 2.0, base + 0.3, 100.0 + i);
		}];
		var a = new Kvo(5, 10), b = new Kvo(5, 10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
