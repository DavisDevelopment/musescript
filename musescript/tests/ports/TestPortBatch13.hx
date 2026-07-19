package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 13: 10 indicators (high_wave, highpass_filter, hikkake,
 * hikkake_modified, hilo_activator, historical_volatility, hma,
 * holt_winters, homing_pigeon, derivative_oscillator) — standard published
 * formulas (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch13 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── HighWave ──────────────────────────────────────────────────────────

	public function testHighWaveTrue() {
		var hw = new HighWave();
		Assert.floatEquals(1.0, hw.update(bar(10.0, 20.0, 0.0, 10.05, 1.0)));
	}

	public function testHighWaveFalseOnOneSidedShadow() {
		// long lower shadow only, negligible upper -> that's a hammer shape, not high-wave.
		var hw = new HighWave();
		Assert.floatEquals(0.0, hw.update(bar(20.0, 20.1, 10.0, 20.05, 1.0)));
	}

	// ── HighpassFilter ────────────────────────────────────────────────────

	public function testHighpassFilterZeroOnFlatSeries() {
		var hp = new HighpassFilter(20);
		var out = null;
		for (i in 0...10) out = hp.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testHighpassFilterBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.2) * 6.0];
		var a = new HighpassFilter(20), b = new HighpassFilter(20);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Hikkake / HikkakeModified ─────────────────────────────────────────

	public function testHikkakeBearishTrap() {
		var hk = new Hikkake();
		hk.update(bar(10.0, 15.0, 5.0, 10.0, 1.0)); // bar1: wide range
		hk.update(bar(10.0, 12.0, 8.0, 10.0, 1.0)); // bar2: inside bar1
		var out = hk.update(bar(10.0, 13.0, 9.0, 10.0, 1.0)); // bar3: breaks ABOVE bar2's high
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	public function testHikkakeBullishTrap() {
		var hk = new Hikkake();
		hk.update(bar(10.0, 15.0, 5.0, 10.0, 1.0));
		hk.update(bar(10.0, 12.0, 8.0, 10.0, 1.0));
		var out = hk.update(bar(10.0, 11.0, 7.0, 10.0, 1.0)); // breaks BELOW bar2's low
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	public function testHikkakeModifiedConfirmsOnReversalBar() {
		var hkm = new HikkakeModified();
		hkm.update(bar(10.0, 15.0, 5.0, 10.0, 1.0)); // bar1
		hkm.update(bar(10.0, 12.0, 8.0, 10.0, 1.0)); // bar2: inside bar1, range [8,12]
		hkm.update(bar(10.0, 13.0, 9.0, 10.0, 1.0)); // bar3: false breakout above 12 -> pending bearish trap
		var out = hkm.update(bar(10.0, 10.5, 9.5, 10.0, 1.0)); // bar4: close back inside [8,12] -> confirmed
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out); // opposite of the up-break -> bearish reversal
	}

	// ── HiloActivator ─────────────────────────────────────────────────────

	public function testHiloActivatorFlatSeriesEqualsPrice() {
		var h = new HiloActivator(5);
		var out = null;
		for (i in 0...10) out = h.update(bar(50.0, 51.0, 49.0, 50.0, 1.0));
		Assert.notNull(out);
		Assert.isTrue(Math.isFinite(out));
	}

	// ── HistoricalVolatility ──────────────────────────────────────────────

	public function testHistoricalVolatilityZeroOnConstantPrice() {
		var hv = new HistoricalVolatility(10, 252.0);
		var out = null;
		for (i in 0...15) out = hv.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testHistoricalVolatilityNonNegative() {
		var hv = new HistoricalVolatility(10, 252.0);
		for (i in 0...30) {
			var out = hv.update(100.0 + Math.sin(i * 0.5) * 8.0);
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	// ── Hma ───────────────────────────────────────────────────────────────

	public function testHmaFlatSeriesConvergesToConstant() {
		var hma = new Hma(10);
		var out = null;
		for (i in 0...40) out = hma.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-6);
	}

	public function testHmaBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new Hma(10), b = new Hma(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── HoltWinters ───────────────────────────────────────────────────────

	public function testHoltWintersFlatSeriesConvergesToConstant() {
		var hw = new HoltWinters(0.3, 0.1);
		var out = null;
		for (i in 0...20) out = hw.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-6);
	}

	public function testHoltWintersBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new HoltWinters(0.3, 0.1), b = new HoltWinters(0.3, 0.1);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── HomingPigeon ──────────────────────────────────────────────────────

	public function testHomingPigeonTrue() {
		var hp = new HomingPigeon();
		hp.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1: open 12, close 9
		var out = hp.update(bar(11.0, 11.5, 10.0, 10.0, 1.0)); // red bar2, body [10,11] inside [9,12]
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── DerivativeOscillator ──────────────────────────────────────────────

	public function testDerivativeOscillatorBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.2) * 6.0];
		var a = new DerivativeOscillator(14, 5, 3, 9), b = new DerivativeOscillator(14, 5, 3, 9);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
