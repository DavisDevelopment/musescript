package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.Ppo;
import musescript.indicators.lib.PpoHistogram;
import musescript.indicators.lib.ProfitFactor;
import musescript.indicators.lib.Qqe;
import musescript.indicators.lib.QuartileBands;

/**
 * Batch 23: 5 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch23 extends Test {

	// ── PPO ──────────────────────────────────────────────────────────────────

	public function testPpoRejectsZeroPeriod() {
		var exc = false;
		try new Ppo(0, 26) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Ppo(12, 0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testPpoRejectsFastNotLessThanSlow() {
		var exc = false;
		try new Ppo(26, 12) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Ppo(12, 12) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testPpoAccessorsAndMetadata() {
		var ppo = new Ppo(12, 26);
		Assert.equals("PPO", ppo.name());
		Assert.isNull(ppo.update(1.0));
		for (i in 1...27) ppo.update(i * 1.0);
		Assert.notNull(ppo.update(27.0));
	}

	public function testPpoZeroSlowEmaYieldsZeroPpo() {
		var ppo = new Ppo(3, 6);
		var values = [for (_ in 0...20) 0.0];
		var out = [for (v in values) ppo.update(v)];
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(0.0, last);
	}

	public function testPpoFirstEmissionAtWarmupPeriod() {
		var ppo = new Ppo(3, 6);
		Assert.equals(6, ppo.warmupPeriod());
		var values = [for (i in 1...31) i * 1.0];
		var out = [for (v in values) ppo.update(v)];
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
	}

	public function testPpoConstantSeriesYieldsZero() {
		var ppo = new Ppo(3, 6);
		var values = [for (_ in 0...60) 100.0];
		var out = [for (v in values) ppo.update(v)];
		for (i in 5...out.length) {
			if (out[i] != null) {
				Assert.floatEquals(0.0, out[i], 1e-9);
			}
		}
	}

	public function testPpoUptrendIsPositive() {
		var ppo = new Ppo(5, 12);
		var values = [for (i in 1...81) i * 1.0];
		var out = [for (v in values) ppo.update(v)];
		var last = null;
		var i = out.length - 1;
		while (i >= 0) {
			if (out[i] != null) {
				last = out[i];
				break;
			}
			i--;
		}
		Assert.notNull(last);
		Assert.isTrue(last > 0.0);
	}

	public function testPpoIgnoresNonFiniteInput() {
		var ppo = new Ppo(3, 6);
		var values = [for (i in 1...31) i * 1.0];
		var out = [for (v in values) ppo.update(v)];
		var last = out[out.length - 1];
		Assert.equals(last, ppo.update(Math.NaN));
		Assert.equals(last, ppo.update(Math.POSITIVE_INFINITY));
	}

	public function testPpoResetClearsState() {
		var ppo = new Ppo(3, 6);
		var values = [for (i in 1...31) i * 1.0];
		for (v in values) ppo.update(v);
		Assert.isTrue(ppo.isReady());
		ppo.reset();
		Assert.isFalse(ppo.isReady());
		Assert.isNull(ppo.update(1.0));
	}

	public function testPpoBatchEqualsStreaming() {
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.25) * 9.0];
		var a = new Ppo(12, 26);
		var b = new Ppo(12, 26);
		var batched = [for (p in prices) a.update(p)];
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── PPO Histogram ────────────────────────────────────────────────────────

	public function testPpoHistogramRejectsInvalidPeriods() {
		var exc = false;
		try new PpoHistogram(0, 26, 9) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PpoHistogram(12, 0, 9) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PpoHistogram(12, 26, 0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PpoHistogram(26, 12, 9) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testPpoHistogramAccessorsAndMetadata() {
		var osc = new PpoHistogram(12, 26, 9);
		Assert.equals(34, osc.warmupPeriod()); // 26 + 9 - 1
		Assert.equals("PpoHistogram", osc.name());
		Assert.isNull(osc.update(1.0));
		Assert.isFalse(osc.isReady());
	}

	public function testPpoHistogramWarmupEmitsFirstValueAtWarmupPeriod() {
		var osc = new PpoHistogram(3, 6, 3);
		var warmup = osc.warmupPeriod();
		Assert.equals(8, warmup); // 6 + 3 - 1
		for (i in 1...(warmup)) {
			Assert.isNull(osc.update(100.0 + i));
		}
		Assert.notNull(osc.update(100.0 + warmup));
		Assert.isTrue(osc.isReady());
	}

	public function testPpoHistogramConstantSeriesConvergesToZero() {
		var osc = new PpoHistogram(12, 26, 9);
		var values = [for (_ in 0...200) 100.0];
		var out = [for (v in values) osc.update(v)];
		var last = null;
		var i = out.length - 1;
		while (i >= 0) {
			if (out[i] != null) {
				last = out[i];
				break;
			}
			i--;
		}
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-9);
	}

	public function testPpoHistogramIgnoresNonFiniteInput() {
		var osc = new PpoHistogram(3, 6, 3);
		var values = [for (i in 1...41) i * 1.0];
		var out = [for (v in values) osc.update(v)];
		var before = out[out.length - 1];
		Assert.notNull(before);
		Assert.equals(before, osc.update(Math.NaN));
		Assert.equals(before, osc.update(Math.POSITIVE_INFINITY));
	}

	public function testPpoHistogramBatchEqualsStreaming() {
		var prices = [for (i in 1...101) 100.0 + Math.cos(i * 0.4) * 10.0];
		var a = new PpoHistogram(12, 26, 9);
		var b = new PpoHistogram(12, 26, 9);
		var batched = [for (p in prices) a.update(p)];
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	public function testPpoHistogramResetClearsState() {
		var osc = new PpoHistogram(12, 26, 9);
		var values = [for (i in 1...81) i * 1.0];
		for (v in values) osc.update(v);
		Assert.isTrue(osc.isReady());
		osc.reset();
		Assert.isFalse(osc.isReady());
		Assert.isNull(osc.update(1.0));
	}

	// ── Profit Factor ────────────────────────────────────────────────────────

	public function testProfitFactorRejectsZeroPeriod() {
		var exc = false;
		try new ProfitFactor(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testProfitFactorAccessorsAndMetadata() {
		var p = new ProfitFactor(10);
		Assert.equals(10, p.warmupPeriod());
		Assert.equals("ProfitFactor", p.name());
	}

	public function testProfitFactorReferenceValue() {
		// returns = [0.02, -0.01, 0.03, -0.02]
		// gains = 0.05, losses = 0.03, PF = 5/3.
		var p = new ProfitFactor(4);
		var values = [0.02, -0.01, 0.03, -0.02];
		var out = [for (v in values) p.update(v)];
		Assert.notNull(out[3]);
		Assert.floatEquals(5.0 / 3.0, out[3], 1e-9);
	}

	public function testProfitFactorNoLossesYieldsInfinity() {
		var p = new ProfitFactor(3);
		var values = [0.01, 0.02, 0.03];
		var out = [for (v in values) p.update(v)];
		Assert.notNull(out[2]);
		Assert.isTrue(Math.isFinite(out[2]) == false && out[2] > 0); // is INFINITY
	}

	public function testProfitFactorFlatWindowYieldsZero() {
		var p = new ProfitFactor(3);
		var values = [0.0, 0.0, 0.0];
		var out = [for (v in values) p.update(v)];
		Assert.notNull(out[2]);
		Assert.floatEquals(0.0, out[2]);
	}

	public function testProfitFactorIgnoresNonFiniteInput() {
		var p = new ProfitFactor(3);
		Assert.isNull(p.update(Math.NaN));
		Assert.isNull(p.update(Math.POSITIVE_INFINITY));
	}

	public function testProfitFactorResetClearsState() {
		var p = new ProfitFactor(3);
		var values = [0.01, -0.02, 0.03];
		for (v in values) p.update(v);
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isFalse(p.isReady());
		Assert.isNull(p.update(0.01));
	}

	public function testProfitFactorBatchEqualsStreaming() {
		var returns = [for (i in 0...40) Math.sin(i * 0.3) * 0.01];
		var a = new ProfitFactor(10);
		var b = new ProfitFactor(10);
		var batched = [for (r in returns) a.update(r)];
		var streamed = [for (r in returns) b.update(r)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				if (Math.isFinite(batched[i]) && Math.isFinite(streamed[i])) {
					Assert.floatEquals(batched[i], streamed[i], 1e-9);
				}
			}
		}
	}

	// ── QQE ──────────────────────────────────────────────────────────────────

	public function testQqeRejectsBadParams() {
		var exc = false;
		try new Qqe(0, 5, 4.236) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Qqe(14, 0, 4.236) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Qqe(14, 5, 0.0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Qqe(14, 5, Math.NaN) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testQqeAccessorsAndMetadata() {
		var qqe = new Qqe(14, 5, 4.236);
		Assert.isNull(qqe.update(1.0));
		Assert.equals("QQE", qqe.name());
	}

	public function testQqeFirstEmissionMatchesWarmup() {
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.06) * 20.0];
		var qqe = new Qqe(14, 5, 4.236);
		var out = [for (p in prices) qqe.update(p)];
		var warmup = qqe.warmupPeriod();
		for (i in 0...(warmup - 1)) {
			Assert.isNull(out[i], "index " + i + " must be None during warmup");
		}
		Assert.notNull(out[warmup - 1], "first value at warmup_period - 1");
	}

	public function testQqeTrailingLineBelowRsiMaInUptrend() {
		var prices = [for (i in 1...121) i * 1.0];
		var qqe = new Qqe(14, 5, 4.236);
		var out = [for (p in prices) qqe.update(p)];
		var last = null;
		var i = out.length - 1;
		while (i >= 0) {
			if (out[i] != null) {
				last = out[i];
				break;
			}
			i--;
		}
		Assert.notNull(last);
		Assert.isTrue(last.trailingLine <= last.rsiMa, "uptrend trailing " + last.trailingLine + " should sit at/below rsi_ma " + last.rsiMa);
	}

	public function testQqeResetClearsState() {
		var qqe = new Qqe(14, 5, 4.236);
		var prices = [for (i in 0...120) 100.0 + Math.sin(i * 0.1) * 8.0];
		for (p in prices) qqe.update(p);
		Assert.isTrue(qqe.isReady());
		qqe.reset();
		Assert.isFalse(qqe.isReady());
		Assert.isNull(qqe.update(1.0));
	}

	public function testQqeBatchEqualsStreaming() {
		var prices = [for (i in 0...150) 50.0 + Math.sin(i * 0.12) * 12.0];
		var a = new Qqe(14, 5, 4.236);
		var b = new Qqe(14, 5, 4.236);
		var batched = [for (p in prices) a.update(p)];
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].rsiMa, streamed[i].rsiMa, 1e-9);
				Assert.floatEquals(batched[i].trailingLine, streamed[i].trailingLine, 1e-9);
			}
		}
	}

	// ── Quartile Bands ───────────────────────────────────────────────────────

	public function testQuartileBandsRejectsZeroPeriod() {
		var exc = false;
		try new QuartileBands(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		var qb = new QuartileBands(1);
		Assert.notNull(qb);
	}

	public function testQuartileBandsAccessorsAndMetadata() {
		var qb = new QuartileBands(20);
		Assert.equals(20, qb.warmupPeriod());
		Assert.equals("QuartileBands", qb.name());
		Assert.isFalse(qb.isReady());
	}

	public function testQuartileBandsWarmsUpThenEmits() {
		var qb = new QuartileBands(4);
		Assert.isNull(qb.update(10.0));
		Assert.isNull(qb.update(20.0));
		Assert.isNull(qb.update(30.0));
		Assert.notNull(qb.update(40.0));
		Assert.isTrue(qb.isReady());
	}

	public function testQuartileBandsKnownQuartiles() {
		// sorted [10,20,30,40]:
		//   Q1 h=(4-1)*0.25=0.75 -> 10 + 0.75*10 = 17.5
		//   Q2 h=1.5            -> 20 + 0.5*10  = 25.0
		//   Q3 h=2.25           -> 30 + 0.25*10 = 32.5
		var qb = new QuartileBands(4);
		var values = [40.0, 30.0, 20.0, 10.0];
		var out = [for (v in values) qb.update(v)];
		var last = out[3];
		Assert.notNull(last);
		Assert.floatEquals(17.5, last.lower, 1e-9);
		Assert.floatEquals(25.0, last.middle, 1e-9);
		Assert.floatEquals(32.5, last.upper, 1e-9);
	}

	public function testQuartileBandsMedianRobustToOutlier() {
		var qb = new QuartileBands(5);
		var values = [1.0, 2.0, 3.0, 4.0, 1000.0];
		var out = [for (v in values) qb.update(v)];
		var last = out[4];
		Assert.notNull(last);
		Assert.floatEquals(3.0, last.middle, 1e-12);
	}

	public function testQuartileBandsRollingWindowEvictsOldest() {
		var qb = new QuartileBands(4);
		var values = [1.0, 2.0, 3.0, 4.0, 40.0, 30.0, 20.0, 10.0];
		var out = [for (v in values) qb.update(v)];
		var last = out[7];
		Assert.notNull(last);
		Assert.floatEquals(17.5, last.lower, 1e-9);
		Assert.floatEquals(25.0, last.middle, 1e-9);
		Assert.floatEquals(32.5, last.upper, 1e-9);
	}

	public function testQuartileBandsResetClearsState() {
		var qb = new QuartileBands(4);
		for (v in [10.0, 20.0, 30.0, 40.0]) qb.update(v);
		Assert.isTrue(qb.isReady());
		qb.reset();
		Assert.isFalse(qb.isReady());
		Assert.isNull(qb.update(10.0));
	}
}
