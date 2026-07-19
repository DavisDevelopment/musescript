package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.PainIndex;
import musescript.indicators.lib.PercentB;
import musescript.indicators.lib.PercentageTrailingStop;
import musescript.indicators.lib.PolarizedFractalEfficiency;

/**
 * Batch 22: 5 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch22 extends Test {
	// ── PainIndex ────────────────────────────────────────────────────────────────────

	public function testPainIndexPureUptrendYieldsZero() {
		// Pure uptrend with period=5 should yield zero drawdowns.
		var prices = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0,
			11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0];
		var ind = new PainIndex(5);
		var out = IndicatorBatch.run(ind, prices);
		for (i in 5...out.length) {
			Assert.notNull(out[i]);
			Assert.floatEquals(0.0, out[i], 1e-12);
		}
	}

	public function testPainIndexReferenceValue() {
		// window [100, 120, 90]: peaks 100,120,120; dd: 0, 0, 0.25.
		// Pain = 0.25 / 3 ≈ 0.08333...
		var prices = [100.0, 120.0, 90.0];
		var ind = new PainIndex(3);
		var out = IndicatorBatch.run(ind, prices);
		Assert.equals(null, out[0]);
		Assert.equals(null, out[1]);
		Assert.notNull(out[2]);
		Assert.floatEquals(0.25 / 3.0, out[2], 1e-12);
	}

	public function testPainIndexNonPositivePeakYieldsZero() {
		// All zeros: peak never positive, so all drawdowns are zero.
		var prices = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
		var ind = new PainIndex(3);
		var out = IndicatorBatch.run(ind, prices);
		for (i in 3...out.length) {
			Assert.notNull(out[i]);
			Assert.equals(0.0, out[i]);
		}
	}

	public function testPainIndexBatchEqualsStreaming() {
		var prices = [for (i in 0...40) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = new PainIndex(10), b = new PainIndex(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-12);
		}
	}

	// ── PercentB ─────────────────────────────────────────────────────────────────────

	public function testPercentBConstantSeriesYieldsMidpoint() {
		// Flat prices: bands collapse, price is exactly mid-band -> 0.5.
		var prices = [for (i in 0...20) 100.0];
		var ind = new PercentB(5, 2.0);
		var out = IndicatorBatch.run(ind, prices);
		// warmup at index 4 (period=5)
		for (i in 4...out.length) {
			Assert.notNull(out[i]);
			Assert.floatEquals(0.5, out[i], 1e-12);
		}
	}

	public function testPercentBPriceAtMiddleIsHalf() {
		// With period=3, multiplier=2, inputs [1.0, 5.0, 3.0] give SMA = 3.0
		// which equals the third price exactly. The price sits on the centre line
		// of symmetric bands, so %b lands on exactly 0.5.
		var prices = [1.0, 5.0, 3.0];
		var ind = new PercentB(3, 2.0);
		var out = IndicatorBatch.run(ind, prices);
		Assert.equals(null, out[0]);
		Assert.equals(null, out[1]);
		Assert.notNull(out[2]);
		Assert.floatEquals(0.5, out[2], 1e-12);
	}

	public function testPercentBBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.cos(i * 0.3) * 7.0];
		var a = new PercentB(20, 2.0), b = new PercentB(20, 2.0);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-12);
		}
	}

	// ── PercentageTrailingStop ───────────────────────────────────────────────────────

	public function testPercentageTrailingStopFirstValueStepBelowPrice() {
		// 100 · 0.10 = 10, so seed stop = 90.
		var prices = [100.0];
		var ind = new PercentageTrailingStop(10.0);
		var out = IndicatorBatch.run(ind, prices);
		Assert.notNull(out[0]);
		Assert.floatEquals(90.0, out[0], 1e-12);
		Assert.isTrue(ind.isReady());
	}

	public function testPercentageTrailingStopLongStopRatchetsUp() {
		// Rising series: each new high pulls the stop up.
		var prices = [100.0, 110.0, 120.0, 130.0];
		var ind = new PercentageTrailingStop(10.0);
		var out = IndicatorBatch.run(ind, prices);
		Assert.floatEquals(90.0, out[0], 1e-9);
		Assert.floatEquals(99.0, out[1], 1e-9);
		Assert.floatEquals(108.0, out[2], 1e-9);
		Assert.floatEquals(117.0, out[3], 1e-9);
	}

	public function testPercentageTrailingStopFlipsToShortOnCloseThrough() {
		// Seed long at 100 -> stop 90.
		// Climb to 130 -> stop ratchets to 117.
		// Crash to 50 -> closes through 117 -> flip to short stop at 55.
		var prices = [100.0, 130.0, 50.0];
		var ind = new PercentageTrailingStop(10.0);
		var out = IndicatorBatch.run(ind, prices);
		ind.update(100.0); // long stop 90
		ind.update(130.0); // ratchet to 117
		var flipped = ind.update(50.0);
		Assert.floatEquals(55.0, flipped, 1e-9);
	}

	public function testPercentageTrailingStopConstantSeriesHoldsStop() {
		var prices = [for (i in 0...30) 100.0];
		var ind = new PercentageTrailingStop(5.0);
		var out = IndicatorBatch.run(ind, prices);
		for (i in 0...out.length) {
			Assert.notNull(out[i]);
			Assert.floatEquals(95.0, out[i], 1e-12);
		}
	}

	public function testPercentageTrailingStopBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = new PercentageTrailingStop(5.0), b = new PercentageTrailingStop(5.0);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-12);
		}
	}

	// ── PolarizedFractalEfficiency ───────────────────────────────────────────────────

	public function testPfeWarmupEmitsAfterPeriodPlusSmoothingPeriods() {
		// raw needs period+1 = 5 closes; EMA(2) needs 2 raws -> first value at
		// input 6 (index 5).
		var prices = [for (i in 0...10) Math.pow(i, 1.0)];
		var ind = new PolarizedFractalEfficiency(4, 2);
		var out = IndicatorBatch.run(ind, prices);
		Assert.equals(null, out[4]);
		Assert.notNull(out[5]);
	}

	public function testPfePerfectUptrendIsStronglyPositive() {
		// A straight ramp: every step is +1, the diagonal is maximally
		// efficient, so PFE saturates near +100.
		var prices = [for (i in 0...30) Math.pow(i, 1.0)];
		var ind = new PolarizedFractalEfficiency(5, 3);
		var out = IndicatorBatch.run(ind, prices);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(last > 99.0, "pfe " + last + " should be near +100");
	}

	public function testPfePerfectDowntrendIsStronglyNegative() {
		var prices = [for (i in 0...30) -Math.pow(i, 1.0)];
		var ind = new PolarizedFractalEfficiency(5, 3);
		var out = IndicatorBatch.run(ind, prices);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(last < -99.0, "pfe " + last + " should be near -100");
	}

	public function testPfeFlatMarketReturnsZero() {
		// No net move over the window -> direction 0 -> raw 0 -> PFE 0.
		var prices = [for (i in 0...20) 10.0];
		var ind = new PolarizedFractalEfficiency(5, 3);
		var out = IndicatorBatch.run(ind, prices);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-12);
	}

	public function testPfeBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new PolarizedFractalEfficiency(10, 5), b = new PolarizedFractalEfficiency(10, 5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-12);
		}
	}
}
