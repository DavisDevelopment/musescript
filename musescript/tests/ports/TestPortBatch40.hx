package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.HtDcPhase;
import musescript.indicators.lib.HtPhasor;
import musescript.indicators.lib.HtTrendMode;
import musescript.indicators.lib.Mama;
import musescript.indicators.lib.SineWave;
import musescript.indicators.lib.SineWeightedMa;
import musescript.indicators.lib.Trendflex;
import musescript.indicators.lib.UniversalOscillator;
import musescript.indicators.lib.Trima;
import musescript.indicators.lib.Smma;
import musescript.indicators.lib.T3;
import musescript.indicators.lib.Tema;
import musescript.indicators.lib.Trix;
import musescript.indicators.lib.Zlema;
import musescript.indicators.lib.Vidya;
import musescript.indicators.lib.Stc;
import musescript.indicators.lib.Pmo;
import musescript.indicators.lib.ZeroLagMacd;
import musescript.indicators.prim.Ema;

/**
 * Batch 40: 18 indicators ported from wickra-core (Ehlers cycle +
 * moving-average family, all f64 series input). Known-value cases are
 * transcribed directly from the Rust fixture blocks; batch_equals_streaming
 * verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch40 extends Test {
	static function sinePrices(n:Int, ?step:Float = 0.4, ?amp:Float = 5.0):Array<Float> {
		return [for (i in 0...n) 100.0 + Math.sin(i * step) * amp];
	}

	static function assertScalarBatchEqualsStreaming(batched:Array<Null<Float>>, streamed:Array<Null<Float>>) {
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── HtDcPhase ────────────────────────────────────────────────────────────

	public function testHtDcPhaseAccessorsAndMetadata() {
		var ht = new HtDcPhase();
		Assert.equals(50, ht.warmupPeriod());
		Assert.equals("HT_DCPHASE", ht.name());
		Assert.isTrue(!ht.isReady());
	}

	public function testHtDcPhaseNearZeroImaginaryCollapsesToSignedNinety() {
		// A near-zero imaginary part makes atan(real/imag) undefined, so the
		// phase collapses to +90 for non-negative real and -90 for negative
		// real before the +90 offset and group-delay correction unwrap it.
		var pos = HtDcPhase.computeDcPhase(1.0, 0.0, 20.0);
		var neg = HtDcPhase.computeDcPhase(-1.0, 0.0, 20.0);
		Assert.isTrue(Math.abs(pos - 198.0) < 1e-9);
		Assert.isTrue(Math.abs(neg - 18.0) < 1e-9);
		// The normal path still flows through atan.
		var mid = HtDcPhase.computeDcPhase(1.0, 1.0, 20.0);
		Assert.isTrue(Math.abs(mid - 153.0) < 1e-9);
	}

	public function testHtDcPhaseEmitsAfterWarmupWithinPhaseBand() {
		var ht = new HtDcPhase();
		var out = IndicatorBatch.run(ht, sinePrices(200));
		Assert.isNull(out[0]);
		Assert.isTrue(ht.isReady());
		for (v in out) {
			if (v == null) continue;
			Assert.isTrue(Math.isFinite(v), "phase must be finite");
			Assert.isTrue(v >= -360.0 && v <= 360.0, 'phase ${v} outside band');
		}
	}

	public function testHtDcPhaseIgnoresNonFiniteInput() {
		var ht = new HtDcPhase();
		IndicatorBatch.run(ht, sinePrices(120));
		var before = ht.value();
		Assert.floatEquals(before, ht.update(Math.NaN));
	}

	public function testHtDcPhaseBatchEqualsStreaming() {
		var prices = sinePrices(200);
		var a = new HtDcPhase();
		var b = new HtDcPhase();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testHtDcPhaseResetClearsState() {
		var ht = new HtDcPhase();
		IndicatorBatch.run(ht, sinePrices(120));
		Assert.isTrue(ht.isReady());
		ht.reset();
		Assert.isTrue(!ht.isReady());
		Assert.isNull(ht.update(100.0));
	}

	// ── HtPhasor ─────────────────────────────────────────────────────────────

	public function testHtPhasorAccessorsAndMetadata() {
		var ht = new HtPhasor();
		Assert.equals(19, ht.warmupPeriod());
		Assert.equals("HT_PHASOR", ht.name());
		Assert.isTrue(!ht.isReady());
	}

	public function testHtPhasorEmitsAfterWarmupAndStaysFinite() {
		var ht = new HtPhasor();
		var out = IndicatorBatch.run(ht, sinePrices(120));
		Assert.isNull(out[0]);
		var first = -1;
		for (i in 0...out.length) {
			if (out[i] != null) { first = i; break; }
		}
		Assert.isTrue(first >= 0, "emits");
		Assert.isTrue(first <= 19, 'first phasor at index ${first}');
		for (o in out) {
			if (o == null) continue;
			Assert.isTrue(Math.isFinite(o.inphase) && Math.isFinite(o.quadrature));
		}
		Assert.isTrue(ht.isReady());
	}

	public function testHtPhasorIgnoresNonFiniteInput() {
		var ht = new HtPhasor();
		IndicatorBatch.run(ht, sinePrices(120));
		// A non-finite input is skipped and produces no value.
		Assert.isNull(ht.update(Math.NaN));
	}

	public function testHtPhasorBatchEqualsStreaming() {
		var prices = sinePrices(150);
		var a = new HtPhasor();
		var b = new HtPhasor();
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].inphase, streamed[i].inphase);
				Assert.floatEquals(batched[i].quadrature, streamed[i].quadrature);
			}
		}
	}

	public function testHtPhasorResetClearsState() {
		var ht = new HtPhasor();
		IndicatorBatch.run(ht, sinePrices(120));
		Assert.isTrue(ht.isReady());
		ht.reset();
		Assert.isTrue(!ht.isReady());
		Assert.isNull(ht.update(100.0));
	}

	// ── HtTrendMode ──────────────────────────────────────────────────────────

	/** A trending ramp followed by a clean cycle, so both modes are exercised. */
	static function mixedPrices():Array<Float> {
		var v:Array<Float> = [];
		for (i in 0...150) v.push(100.0 + i * 0.8);
		for (i in 0...200) v.push(220.0 + Math.sin(i * 0.45) * 12.0);
		return v;
	}

	public function testHtTrendModeAccessorsAndMetadata() {
		var ht = new HtTrendMode();
		Assert.equals(50, ht.warmupPeriod());
		Assert.equals("HT_TRENDMODE", ht.name());
		Assert.isTrue(!ht.isReady());
		Assert.isNull(ht.value());
	}

	public function testHtTrendModeEmitsBinaryFlagAndVisitsBothModes() {
		var ht = new HtTrendMode();
		var out = IndicatorBatch.run(ht, mixedPrices());
		Assert.isNull(out[0]);
		Assert.isTrue(ht.isReady());
		var sawTrend = false;
		var sawCycle = false;
		for (v in out) {
			if (v == null) continue;
			Assert.isTrue(v == 0.0 || v == 1.0, 'trend mode must be binary, got ${v}');
			if (v == 1.0) sawTrend = true else sawCycle = true;
		}
		Assert.isTrue(sawTrend, "ramp segment should report trend mode");
		Assert.isTrue(sawCycle, "cycle segment should report cycle mode");
	}

	public function testHtTrendModeIgnoresNonFiniteInput() {
		var ht = new HtTrendMode();
		IndicatorBatch.run(ht, mixedPrices());
		var before = ht.value();
		Assert.floatEquals(before, ht.update(Math.NaN));
	}

	public function testHtTrendModeBatchEqualsStreaming() {
		var prices = mixedPrices();
		var a = new HtTrendMode();
		var b = new HtTrendMode();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testHtTrendModeResetClearsState() {
		var ht = new HtTrendMode();
		IndicatorBatch.run(ht, mixedPrices());
		Assert.isTrue(ht.isReady());
		ht.reset();
		Assert.isTrue(!ht.isReady());
		Assert.isNull(ht.update(100.0));
	}

	// ── Mama ─────────────────────────────────────────────────────────────────

	public function testMamaRejectsInvalidLimits() {
		var cases = [
			{fast: 0.0, slow: 0.05},
			{fast: 0.5, slow: 0.0},
			{fast: 0.05, slow: 0.5},
			{fast: 1.5, slow: 0.05},
			{fast: Math.NaN, slow: 0.05},
		];
		for (c in cases) {
			try {
				new Mama(c.fast, c.slow);
				Assert.fail('Should reject limits (${c.fast}, ${c.slow})');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testMamaAccessorsAndMetadata() {
		var mama = Mama.classic();
		var lim = mama.limits();
		Assert.floatEquals(0.5, lim.fast_limit);
		Assert.floatEquals(0.05, lim.slow_limit);
		Assert.equals(33, mama.warmupPeriod());
		Assert.equals("MAMA", mama.name());
		Assert.isTrue(!mama.isReady());
		for (i in 0...60) {
			mama.update(100.0 + Math.sin(i * 0.3) * 5.0);
		}
		Assert.isTrue(mama.isReady());
		Assert.notNull(mama.value());
	}

	public function testMamaFamaLagsOrEqualsMamaOnConstantSeries() {
		var mama = Mama.classic();
		var out = IndicatorBatch.run(mama, [for (_ in 0...200) 100.0]);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		// On a flat series both lines converge to the price.
		Assert.isTrue(Math.abs(last.mama - 100.0) < 1.0);
		Assert.isTrue(Math.abs(last.fama - 100.0) < 1.0);
	}

	public function testMamaBatchEqualsStreaming() {
		var prices = [for (i in 0...120) 100.0 + Math.sin(i * 0.25) * 5.0];
		var a = Mama.classic();
		var b = Mama.classic();
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].mama, streamed[i].mama);
				Assert.floatEquals(batched[i].fama, streamed[i].fama);
			}
		}
	}

	public function testMamaIgnoresNonFiniteInput() {
		var mama = Mama.classic();
		IndicatorBatch.run(mama, [for (i in 0...100) 100.0 + Math.sin(i * 0.3) * 5.0]);
		var before = mama.value();
		Assert.notNull(before);
		var after = mama.update(Math.NaN);
		Assert.floatEquals(before.mama, after.mama);
		Assert.floatEquals(before.fama, after.fama);
	}

	public function testMamaResetClearsState() {
		var mama = Mama.classic();
		IndicatorBatch.run(mama, [for (i in 0...100) 100.0 + Math.sin(i * 0.3) * 5.0]);
		Assert.isTrue(mama.isReady());
		mama.reset();
		Assert.isTrue(!mama.isReady());
	}

	public function testMamaFlatInputUsesPhaseFallback() {
		// Zero inputs make every smooth/detrender term arithmetically exact
		// zero, so `i1 == 0.0` and the phase calculation takes the prev-phase
		// fallback rather than atan(q1/i1).
		var mama = Mama.classic();
		var out = IndicatorBatch.run(mama, [for (_ in 0...200) 0.0]);
		var count = 0;
		for (v in out) if (v != null) count++;
		Assert.isTrue(count > 100);
	}

	// ── SineWave ─────────────────────────────────────────────────────────────

	public function testSineWaveAccessorsAndMetadata() {
		var sw = new SineWave();
		Assert.equals(50, sw.warmupPeriod());
		Assert.equals("SineWave", sw.name());
		Assert.isTrue(!sw.isReady());
		Assert.isNull(sw.value());
		IndicatorBatch.run(sw, sinePrices(120));
		Assert.isTrue(sw.isReady());
		Assert.notNull(sw.value());
	}

	public function testSineWaveOutputBounded() {
		var prices = [for (i in 0...200) 100.0 + Math.cos(i * 0.3) * 5.0];
		var sw = new SineWave();
		for (v in IndicatorBatch.run(sw, prices)) {
			if (v == null) continue;
			Assert.isTrue(v >= -1.0 && v <= 1.0, 'sine out of bounds: ${v}');
		}
		// Lead value also bounded after warmup.
		Assert.isTrue(sw.lead() >= -1.0 && sw.lead() <= 1.0);
	}

	public function testSineWaveBatchEqualsStreaming() {
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new SineWave();
		var b = new SineWave();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testSineWaveIgnoresNonFiniteInput() {
		var sw = new SineWave();
		IndicatorBatch.run(sw, sinePrices(120));
		var before = sw.value();
		Assert.notNull(before);
		Assert.floatEquals(before, sw.update(Math.NaN));
	}

	public function testSineWaveResetClearsState() {
		var sw = new SineWave();
		IndicatorBatch.run(sw, sinePrices(120));
		Assert.isTrue(sw.isReady());
		sw.reset();
		Assert.isTrue(!sw.isReady());
		Assert.isNull(sw.value());
	}

	public function testSineWaveFlatInputUsesPhaseFallback() {
		// Zero inputs deterministically take the last-phase fallback branch.
		var sw = new SineWave();
		IndicatorBatch.run(sw, [for (_ in 0...120) 0.0]);
		Assert.notNull(sw.value());
	}

	// ── SineWeightedMa ───────────────────────────────────────────────────────

	public function testSineWeightedMaRejectsZeroPeriod() {
		try {
			new SineWeightedMa(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testSineWeightedMaAccessorsAndMetadata() {
		var swma = new SineWeightedMa(7);
		Assert.equals(7, swma.getPeriod());
		Assert.equals(7, swma.warmupPeriod());
		Assert.equals("SWMA", swma.name());
	}

	public function testSineWeightedMaWarmupReturnsNone() {
		var swma = new SineWeightedMa(3);
		Assert.isNull(swma.update(1.0));
		Assert.isNull(swma.update(2.0));
		// SWMA(3): weights sin(pi/4), sin(pi/2), sin(3pi/4) = [√½, 1, √½].
		// Over [1,2,3]: (√½·1 + 1·2 + √½·3) / (√½ + 1 + √½).
		var s = 1.0 / Math.sqrt(2.0);
		var total = s + 1.0 + s;
		var want = (s * 1.0 + 1.0 * 2.0 + s * 3.0) / total;
		Assert.floatEquals(want, swma.update(3.0), 1e-12);
	}

	public function testSineWeightedMaSymmetricWeightsGiveMidpointOnLinearWindow() {
		// For a perfectly linear window the symmetric weighting reproduces the
		// arithmetic centre of the window.
		var swma = new SineWeightedMa(5);
		var v = IndicatorBatch.run(swma, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.floatEquals(3.0, v[4], 1e-12);
	}

	public function testSineWeightedMaPeriodOneIsPassThrough() {
		var swma = new SineWeightedMa(1);
		Assert.floatEquals(5.5, swma.update(5.5), 1e-12);
		Assert.floatEquals(7.5, swma.update(7.5), 1e-12);
	}

	public function testSineWeightedMaResetClearsState() {
		var swma = new SineWeightedMa(4);
		IndicatorBatch.run(swma, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(swma.isReady());
		swma.reset();
		Assert.isTrue(!swma.isReady());
		Assert.isNull(swma.update(10.0));
	}

	public function testSineWeightedMaBatchEqualsStreaming() {
		var prices = [for (i in 1...21) i * 0.5];
		var a = new SineWeightedMa(5);
		var b = new SineWeightedMa(5);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testSineWeightedMaIgnoresNonFiniteInputButKeepsState() {
		var swma = new SineWeightedMa(3);
		swma.update(1.0);
		swma.update(2.0);
		var ready = swma.update(3.0);
		Assert.notNull(ready);
		Assert.floatEquals(ready, swma.update(Math.NaN));
		Assert.floatEquals(ready, swma.update(Math.POSITIVE_INFINITY));
		// The window still holds 1, 2, 3 -> next real input slides it to 2, 3, 4.
		var s = 1.0 / Math.sqrt(2.0);
		var total = s + 1.0 + s;
		var want = (s * 2.0 + 1.0 * 3.0 + s * 4.0) / total;
		Assert.floatEquals(want, swma.update(4.0), 1e-12);
	}

	// ── Trendflex ────────────────────────────────────────────────────────────

	public function testTrendflexRejectsZeroPeriod() {
		try {
			new Trendflex(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTrendflexAccessorsAndMetadata() {
		var t = new Trendflex(20);
		Assert.equals(20, t.getPeriod());
		Assert.equals(21, t.warmupPeriod());
		Assert.equals("Trendflex", t.name());
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
	}

	public function testTrendflexFirstEmissionAtWarmupPeriod() {
		var t = new Trendflex(5);
		var xs = [for (i in 0...12) (i : Float)];
		var out = IndicatorBatch.run(t, xs);
		for (i in 0...5) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[5]);
	}

	public function testTrendflexConstantInputIsZero() {
		var t = new Trendflex(10);
		for (v in IndicatorBatch.run(t, [for (_ in 0...100) 50.0])) {
			if (v == null) continue;
			Assert.floatEquals(0.0, v, 1e-9);
		}
	}

	public function testTrendflexUptrendIsPositive() {
		// A steady rise keeps the current filtered value above its past values.
		var t = new Trendflex(10);
		var out = IndicatorBatch.run(t, [for (i in 0...200) (i : Float)]);
		var emitted:Array<Float> = [];
		for (v in out) if (v != null) emitted.push(v);
		for (i in 100...emitted.length) {
			Assert.isTrue(emitted[i] > 0.0, 'uptrend should be positive, got ${emitted[i]}');
		}
	}

	public function testTrendflexDowntrendIsNegative() {
		var t = new Trendflex(10);
		var out = IndicatorBatch.run(t, [for (i in 0...200) 200.0 - i]);
		var emitted:Array<Float> = [];
		for (v in out) if (v != null) emitted.push(v);
		for (i in 100...emitted.length) {
			Assert.isTrue(emitted[i] < 0.0, 'downtrend should be negative, got ${emitted[i]}');
		}
	}

	public function testTrendflexIgnoresNonFinite() {
		var t = new Trendflex(10);
		IndicatorBatch.run(t, [for (i in 0...40) (i : Float)]);
		var before = t.value();
		Assert.floatEquals(before, t.update(Math.NaN));
	}

	public function testTrendflexResetClearsState() {
		var t = new Trendflex(10);
		IndicatorBatch.run(t, [for (i in 0...40) (i : Float)]);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
	}

	public function testTrendflexBatchEqualsStreaming() {
		var xs = [for (i in 0...120) 100.0 + Math.sin(i * 0.25) * 9.0];
		var a = new Trendflex(20);
		var b = new Trendflex(20);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, xs), [for (x in xs) b.update(x)]);
	}

	// ── UniversalOscillator ──────────────────────────────────────────────────

	public function testUniversalOscillatorRejectsZeroPeriod() {
		try {
			new UniversalOscillator(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testUniversalOscillatorAccessorsAndMetadata() {
		var u = new UniversalOscillator(20);
		Assert.equals(20, u.getPeriod());
		Assert.equals(3, u.warmupPeriod());
		Assert.equals("UniversalOscillator", u.name());
		Assert.isTrue(!u.isReady());
		Assert.isNull(u.value());
	}

	public function testUniversalOscillatorFirstEmissionAtWarmupPeriod() {
		var u = new UniversalOscillator(20);
		var out = IndicatorBatch.run(u, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.notNull(out[2]);
	}

	public function testUniversalOscillatorConstantInputIsZero() {
		// A flat input whitens to zero -> output 0.
		var u = new UniversalOscillator(20);
		for (v in IndicatorBatch.run(u, [for (_ in 0...200) 50.0])) {
			if (v == null) continue;
			Assert.isTrue(Math.abs(v) < 1e-9);
		}
	}

	public function testUniversalOscillatorOutputInRange() {
		var u = new UniversalOscillator(20);
		var xs = [for (i in 0...400) 100.0 + Math.sin(2.0 * Math.PI * i / 20.0) * 5.0];
		for (v in IndicatorBatch.run(u, xs)) {
			if (v == null) continue;
			Assert.isTrue(v >= -1.0 && v <= 1.0, 'out of range: ${v}');
		}
	}

	public function testUniversalOscillatorCyclicInputSwingsBothSigns() {
		var u = new UniversalOscillator(20);
		var xs = [for (i in 0...400) 100.0 + Math.sin(2.0 * Math.PI * i / 20.0) * 5.0];
		var out = IndicatorBatch.run(u, xs);
		var emitted:Array<Float> = [];
		for (v in out) if (v != null) emitted.push(v);
		var sawHigh = false;
		var sawLow = false;
		for (i in 100...emitted.length) {
			if (emitted[i] > 0.5) sawHigh = true;
			if (emitted[i] < -0.5) sawLow = true;
		}
		Assert.isTrue(sawHigh);
		Assert.isTrue(sawLow);
	}

	public function testUniversalOscillatorIgnoresNonFinite() {
		var u = new UniversalOscillator(20);
		IndicatorBatch.run(u, [for (i in 0...40) 100.0 + Math.sin(i * 0.3)]);
		var before = u.value();
		Assert.floatEquals(before, u.update(Math.NaN));
	}

	public function testUniversalOscillatorResetClearsState() {
		var u = new UniversalOscillator(20);
		IndicatorBatch.run(u, [for (i in 0...40) 100.0 + Math.sin(i * 0.3)]);
		Assert.isTrue(u.isReady());
		u.reset();
		Assert.isTrue(!u.isReady());
		Assert.isNull(u.value());
	}

	public function testUniversalOscillatorBatchEqualsStreaming() {
		var xs = [for (i in 0...120) 100.0 + Math.sin(i * 0.25) * 9.0];
		var a = new UniversalOscillator(20);
		var b = new UniversalOscillator(20);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, xs), [for (x in xs) b.update(x)]);
	}

	public function testUniversalOscillatorNonFiniteWhiteNoiseIsSkipped() {
		// `price - p2` can overflow to infinity even when both prices are
		// finite; the non-finite white-noise term must be skipped.
		var u = new UniversalOscillator(20);
		Assert.isNull(u.update(-1e308));
		Assert.isNull(u.update(0.0));
		// (1e308 - (-1e308)) overflows to +inf -> white_noise non-finite.
		Assert.isNull(u.update(1e308));
	}

	// ── Trima ────────────────────────────────────────────────────────────────

	public function testTrimaRejectsZeroPeriod() {
		try {
			new Trima(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTrimaAccessorsAndMetadata() {
		var t = new Trima(5);
		Assert.equals(5, t.getPeriod());
		Assert.equals("TRIMA", t.name());
		Assert.isNull(t.value());
		for (i in 1...t.warmupPeriod() + 1) {
			t.update(i);
		}
		Assert.notNull(t.value());
	}

	public function testTrimaOddPeriodReferenceValues() {
		// TRIMA(5) is SMA(3) of SMA(3).
		// SMA(3) of 1..=7 -> [_,_,2,3,4,5,6]; SMA(3) of that -> [_,_,_,_,3,4,5].
		var trima = new Trima(5);
		var out = IndicatorBatch.run(trima, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[3]);
		Assert.floatEquals(3.0, out[4], 1e-12);
		Assert.floatEquals(4.0, out[5], 1e-12);
		Assert.floatEquals(5.0, out[6], 1e-12);
	}

	public function testTrimaFirstEmissionAtWarmupPeriod() {
		// Even period: TRIMA(6) -> SMA(3) of SMA(4); first value at input 6.
		var trima = new Trima(6);
		var out = IndicatorBatch.run(trima, [for (i in 1...11) (i : Float)]);
		Assert.equals(6, trima.warmupPeriod());
		for (i in 0...5) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[5]);
	}

	public function testTrimaConstantSeriesYieldsTheConstant() {
		var trima = new Trima(7);
		var out = IndicatorBatch.run(trima, [for (_ in 0...20) 42.0]);
		for (i in 6...out.length) {
			Assert.floatEquals(42.0, out[i], 1e-12);
		}
	}

	public function testTrimaIgnoresNonFiniteInput() {
		var trima = new Trima(5);
		var ready = IndicatorBatch.run(trima, [1.0, 2.0, 3.0, 4.0, 5.0]);
		var last = ready[4];
		Assert.notNull(last);
		Assert.floatEquals(last, trima.update(Math.NaN));
	}

	public function testTrimaResetClearsState() {
		var trima = new Trima(5);
		IndicatorBatch.run(trima, [for (i in 1...11) (i : Float)]);
		Assert.isTrue(trima.isReady());
		trima.reset();
		Assert.isTrue(!trima.isReady());
		Assert.isNull(trima.update(1.0));
	}

	public function testTrimaBatchEqualsStreaming() {
		var prices = [for (i in 1...41) (i : Float)];
		var a = new Trima(8);
		var b = new Trima(8);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Smma ─────────────────────────────────────────────────────────────────

	public function testSmmaRejectsZeroPeriod() {
		try {
			new Smma(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testSmmaAccessorsAndMetadata() {
		var smma = new Smma(7);
		Assert.equals(7, smma.getPeriod());
		Assert.equals(7, smma.warmupPeriod());
		Assert.equals("SMMA", smma.name());
		Assert.isNull(smma.value());
		for (i in 1...8) {
			smma.update(i);
		}
		Assert.notNull(smma.value());
	}

	public function testSmmaWarmupThenRecurrence() {
		// SMMA(3): seed = SMA(1,2,3) = 2.0; then (prev*2 + x) / 3.
		var smma = new Smma(3);
		Assert.isNull(smma.update(1.0));
		Assert.isNull(smma.update(2.0));
		Assert.floatEquals(2.0, smma.update(3.0));
		Assert.floatEquals((2.0 * 2.0 + 4.0) / 3.0, smma.update(4.0), 1e-12);
		Assert.floatEquals(((2.0 * 2.0 + 4.0) / 3.0 * 2.0 + 5.0) / 3.0, smma.update(5.0), 1e-12);
	}

	public function testSmmaPeriodOneIsPassThrough() {
		var smma = new Smma(1);
		Assert.floatEquals(5.0, smma.update(5.0));
		Assert.floatEquals(10.0, smma.update(10.0));
	}

	public function testSmmaConstantSeriesYieldsTheConstant() {
		var smma = new Smma(5);
		var out = IndicatorBatch.run(smma, [for (_ in 0...20) 7.0]);
		for (i in 4...out.length) {
			Assert.floatEquals(7.0, out[i], 1e-12);
		}
	}

	public function testSmmaIgnoresNonFiniteInput() {
		var smma = new Smma(3);
		IndicatorBatch.run(smma, [1.0, 2.0, 3.0]);
		Assert.floatEquals(2.0, smma.update(Math.NaN));
		Assert.floatEquals(2.0, smma.update(Math.POSITIVE_INFINITY));
	}

	public function testSmmaResetClearsState() {
		var smma = new Smma(3);
		IndicatorBatch.run(smma, [1.0, 2.0, 3.0, 4.0]);
		Assert.isTrue(smma.isReady());
		smma.reset();
		Assert.isTrue(!smma.isReady());
		Assert.isNull(smma.update(10.0));
	}

	public function testSmmaBatchEqualsStreaming() {
		var prices = [for (i in 1...31) (i : Float)];
		var a = new Smma(7);
		var b = new Smma(7);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── T3 ───────────────────────────────────────────────────────────────────

	public function testT3RejectsZeroPeriod() {
		try {
			new T3(0, 0.7);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testT3RejectsOutOfRangeVolumeFactor() {
		for (v in [-0.1, 1.5, Math.NaN]) {
			try {
				new T3(5, v);
				Assert.fail('Should reject volume factor ${v}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
		Assert.notNull(new T3(5, 0.0));
		Assert.notNull(new T3(5, 1.0));
	}

	public function testT3AccessorsAndMetadata() {
		var t3 = new T3(5, 0.7);
		Assert.equals(5, t3.getPeriod());
		Assert.floatEquals(0.7, t3.volumeFactor(), 1e-12);
		Assert.equals("T3", t3.name());
		Assert.isNull(t3.value());
		for (_ in 0...t3.warmupPeriod()) {
			t3.update(50.0);
		}
		Assert.notNull(t3.value());
	}

	public function testT3CoefficientsSumToOne() {
		// c1 + c2 + c3 + c4 == 1 for any v, so a constant series is preserved.
		for (v in [0.0, 0.3, 0.7, 1.0]) {
			var t3 = new T3(5, v);
			Assert.floatEquals(1.0, t3.c1 + t3.c2 + t3.c3 + t3.c4, 1e-12);
		}
	}

	public function testT3FirstEmissionAtWarmupPeriod() {
		var t3 = new T3(4, 0.7);
		Assert.equals(6 * 4 - 5, t3.warmupPeriod());
		var out = IndicatorBatch.run(t3, [for (i in 1...61) (i : Float)]);
		for (i in 0...t3.warmupPeriod() - 1) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[t3.warmupPeriod() - 1]);
	}

	public function testT3ConstantSeriesYieldsTheConstant() {
		var t3 = new T3(6, 0.7);
		var out = IndicatorBatch.run(t3, [for (_ in 0...80) 50.0]);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(50.0, last, 1e-9);
	}

	public function testT3ZeroVolumeFactorCollapsesToTripleCascadedEma() {
		// With v = 0 the coefficients are c1=c2=c3=0, c4=1, so T3 == e3.
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.2) * 9.0];
		var t3 = new T3(5, 0.0);
		var got = IndicatorBatch.run(t3, prices);

		var e1 = new Ema(5);
		var e2 = new Ema(5);
		var e3 = new Ema(5);
		var want:Array<Null<Float>> = [for (p in prices) {
			var a = e1.update(p);
			if (a == null) null else {
				var b = e2.update(a);
				if (b == null) null else e3.update(b);
			}
		}];

		for (i in (t3.warmupPeriod() - 1)...prices.length) {
			Assert.floatEquals(want[i], got[i], 1e-9);
		}
	}

	public function testT3IgnoresNonFiniteInput() {
		var t3 = new T3(4, 0.7);
		var out = IndicatorBatch.run(t3, [for (i in 1...61) (i : Float)]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(last, t3.update(Math.NaN));
		Assert.floatEquals(last, t3.update(Math.POSITIVE_INFINITY));
	}

	public function testT3ResetClearsState() {
		var t3 = new T3(4, 0.7);
		IndicatorBatch.run(t3, [for (i in 1...61) (i : Float)]);
		Assert.isTrue(t3.isReady());
		t3.reset();
		Assert.isTrue(!t3.isReady());
		Assert.isNull(t3.update(1.0));
	}

	public function testT3BatchEqualsStreaming() {
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.25) * 7.0];
		var a = new T3(7, 0.7);
		var b = new T3(7, 0.7);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Tema ─────────────────────────────────────────────────────────────────

	public function testTemaConstantSeriesYieldsConstantTema() {
		var tema = new Tema(5);
		var out = IndicatorBatch.run(tema, [for (_ in 0...80) 42.0]);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(42.0, last, 1e-9);
	}

	public function testTemaBatchEqualsStreaming() {
		var prices = [for (i in 1...81) Math.sin(i * 0.3) * 10.0];
		var a = new Tema(5);
		var b = new Tema(5);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testTemaResetClearsState() {
		var tema = new Tema(5);
		IndicatorBatch.run(tema, [for (i in 1...81) (i : Float)]);
		Assert.isTrue(tema.isReady());
		tema.reset();
		Assert.isTrue(!tema.isReady());
	}

	public function testTemaRejectsZeroPeriod() {
		try {
			new Tema(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTemaAccessorsAndMetadata() {
		var tema = new Tema(5);
		Assert.equals(5, tema.getPeriod());
		// EMA1 seeds at period (5), each cascade stage needs another (period-1) inputs.
		Assert.equals(3 * 5 - 2, tema.warmupPeriod());
		Assert.equals("TEMA", tema.name());
	}

	// ── Trix ─────────────────────────────────────────────────────────────────

	public function testTrixConstantSeriesYieldsZeroTrix() {
		var trix = new Trix(5);
		var out = IndicatorBatch.run(trix, [for (_ in 0...80) 100.0]);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(0.0, last, 1e-9);
	}

	public function testTrixRisingSeriesEventuallyPositiveTrix() {
		var prices = [for (i in 1...201) (i : Float)];
		var trix = new Trix(5);
		var out = IndicatorBatch.run(trix, prices);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.isTrue(last > 0.0);
	}

	public function testTrixBatchEqualsStreaming() {
		var prices = [for (i in 1...81) i * 1.3];
		var a = new Trix(7);
		var b = new Trix(7);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testTrixResetClearsState() {
		var trix = new Trix(5);
		IndicatorBatch.run(trix, [for (i in 1...81) (i : Float)]);
		Assert.isTrue(trix.isReady());
		trix.reset();
		Assert.isTrue(!trix.isReady());
	}

	public function testTrixRejectsZeroPeriod() {
		try {
			new Trix(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTrixAccessorsAndMetadata() {
		var trix = new Trix(5);
		Assert.equals(5, trix.getPeriod());
		// Triple EMA seeds at 3*5-2 = 13; +1 for the rate-of-change pair = 14.
		Assert.equals(14, trix.warmupPeriod());
		Assert.equals("TRIX", trix.name());
	}

	public function testTrixZeroInputSeriesYieldsZeroTrix() {
		// All-zero inputs collapse every EMA stage to 0.0; once warmed the
		// prev == 0.0 fallback branch must return 0.0, not divide by zero.
		var trix = new Trix(3);
		var out = IndicatorBatch.run(trix, [for (_ in 0...20) 0.0]);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.floatEquals(0.0, last);
	}

	// ── Zlema ────────────────────────────────────────────────────────────────

	public function testZlemaRejectsZeroPeriod() {
		try {
			new Zlema(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testZlemaAccessorsAndMetadata() {
		var z = new Zlema(5);
		Assert.equals(5, z.getPeriod());
		Assert.equals("ZLEMA", z.name());
		Assert.isNull(z.value());
		for (i in 1...z.warmupPeriod() + 1) {
			z.update(i);
		}
		Assert.notNull(z.value());
	}

	public function testZlemaLagIsHalfOfPeriodMinusOne() {
		Assert.equals(1, new Zlema(3).getLag());
		Assert.equals(4, new Zlema(10).getLag());
		Assert.equals(0, new Zlema(1).getLag());
	}

	public function testZlemaReferenceValues() {
		// ZLEMA(3): lag = 1, de_lagged_t = 2·xt − x_{t-1}, then EMA(3).
		// [1,2,3,4,5] -> de-lagged [_, 3, 4, 5, 6]; EMA(3) seeds at the third
		// de-lagged value: mean(3,4,5) = 4.0; next = 0.5·6 + 0.5·4 = 5.0.
		var zlema = new Zlema(3);
		Assert.equals(4, zlema.warmupPeriod());
		var out = IndicatorBatch.run(zlema, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.isNull(out[2]);
		Assert.floatEquals(4.0, out[3], 1e-12);
		Assert.floatEquals(5.0, out[4], 1e-12);
	}

	public function testZlemaConstantSeriesYieldsTheConstant() {
		// De-lagging a constant gives the same constant (2c − c = c).
		var zlema = new Zlema(7);
		var out = IndicatorBatch.run(zlema, [for (_ in 0...60) 33.0]);
		for (i in (zlema.warmupPeriod() - 1)...out.length) {
			if (out[i] == null) continue;
			Assert.floatEquals(33.0, out[i], 1e-9);
		}
	}

	public function testZlemaIgnoresNonFiniteInput() {
		var zlema = new Zlema(3);
		var out = IndicatorBatch.run(zlema, [1.0, 2.0, 3.0, 4.0, 5.0]);
		var last = out[4];
		Assert.notNull(last);
		Assert.floatEquals(last, zlema.update(Math.NaN));
		Assert.floatEquals(last, zlema.update(Math.POSITIVE_INFINITY));
	}

	public function testZlemaResetClearsState() {
		var zlema = new Zlema(5);
		IndicatorBatch.run(zlema, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(zlema.isReady());
		zlema.reset();
		Assert.isTrue(!zlema.isReady());
		Assert.isNull(zlema.update(1.0));
	}

	public function testZlemaBatchEqualsStreaming() {
		var prices = [for (i in 1...61) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = new Zlema(9);
		var b = new Zlema(9);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Vidya ────────────────────────────────────────────────────────────────

	public function testVidyaRejectsZeroPeriod() {
		try {
			new Vidya(0, 9);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Vidya(14, 0);
			Assert.fail("Should reject cmo_period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testVidyaAccessorsAndMetadata() {
		var v = new Vidya(14, 9);
		var p = v.periods();
		Assert.equals(14, p.period);
		Assert.equals(9, p.cmo_period);
		Assert.equals(10, v.warmupPeriod());
		Assert.equals("VIDYA", v.name());
	}

	public function testVidyaConstantSeriesYieldsTheConstant() {
		// Flat input -> CMO = 0 -> alpha = 0 -> VIDYA holds its seed value.
		var v = new Vidya(14, 4);
		var out = IndicatorBatch.run(v, [for (_ in 0...30) 42.0]);
		for (i in 4...out.length) {
			if (out[i] == null) continue;
			Assert.floatEquals(42.0, out[i], 1e-12);
		}
	}

	public function testVidyaPureUptrendAlphaEqualsBase() {
		// Monotonic uptrend: CMO saturates at +100, so alpha = alpha_base.
		var v = new Vidya(2, 4);
		var prices = [for (i in 1...41) (i : Float)];
		var out = IndicatorBatch.run(v, prices);
		var last = out[out.length - 1];
		var latest = prices[prices.length - 1];
		Assert.isTrue(Math.abs(latest - last) < 2.0,
			'VIDYA should track close on a clean uptrend: ${last} vs ${latest}');
	}

	public function testVidyaWarmupEmitsFirstValueAtCmoPeriodPlusOne() {
		var v = new Vidya(14, 3);
		Assert.equals(4, v.warmupPeriod());
		Assert.isNull(v.update(10.0));
		Assert.isNull(v.update(11.0));
		Assert.isNull(v.update(12.0));
		Assert.notNull(v.update(13.0));
	}

	public function testVidyaBatchEqualsStreaming() {
		var prices = [for (i in 1...61) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = new Vidya(14, 9);
		var b = new Vidya(14, 9);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testVidyaResetClearsState() {
		var v = new Vidya(14, 9);
		IndicatorBatch.run(v, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(1.0));
	}

	public function testVidyaIgnoresNonFiniteInput() {
		var v = new Vidya(14, 4);
		IndicatorBatch.run(v, [for (i in 1...21) (i : Float)]);
		var before = v.update(21.0);
		Assert.notNull(before);
		Assert.floatEquals(before, v.update(Math.NaN));
		Assert.floatEquals(before, v.update(Math.POSITIVE_INFINITY));
	}

	// ── Stc ──────────────────────────────────────────────────────────────────

	public function testStcRejectsZeroPeriod() {
		var cases = [
			{fast: 0, slow: 50, p: 10},
			{fast: 23, slow: 0, p: 10},
			{fast: 23, slow: 50, p: 0},
		];
		for (c in cases) {
			try {
				new Stc(c.fast, c.slow, c.p, 0.5);
				Assert.fail('Should reject (${c.fast}, ${c.slow}, ${c.p})');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testStcRejectsInvalidParams() {
		// fast >= slow
		try {
			new Stc(50, 23, 10, 0.5);
			Assert.fail("Should reject fast >= slow");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		for (factor in [0.0, 1.5, Math.NaN]) {
			try {
				new Stc(23, 50, 10, factor);
				Assert.fail('Should reject factor ${factor}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testStcAccessorsAndMetadata() {
		var stc = Stc.classic();
		var p = stc.params();
		Assert.equals(23, p.fast);
		Assert.equals(50, p.slow);
		Assert.equals(10, p.schaff_period);
		Assert.isTrue(Math.abs(p.factor - 0.5) < 1e-12);
		Assert.equals(50 + 18, stc.warmupPeriod());
		Assert.equals("STC", stc.name());
	}

	public function testStcConstantSeriesYieldsZero() {
		// Flat input -> macd is 0 every bar -> stochastic-on-flat-window
		// returns 0 -> d stays at 0 -> %K2 returns 0 -> STC stays at 0.
		var stc = new Stc(3, 5, 4, 0.5);
		var out = IndicatorBatch.run(stc, [for (_ in 0...80) 42.0]);
		var seen = 0;
		var i = out.length - 1;
		while (i >= 0 && seen < 5) {
			if (out[i] != null) {
				Assert.floatEquals(0.0, out[i]);
				seen++;
			}
			i--;
		}
		Assert.equals(5, seen);
	}

	public function testStcWarmupEmitsFirstValueAtWarmupPeriod() {
		var stc = new Stc(2, 4, 3, 0.5);
		// slow(4) + 2*(3-1) = 8.
		Assert.equals(8, stc.warmupPeriod());
		var prices = [for (i in 1...11) (i : Float)];
		var out = IndicatorBatch.run(stc, prices);
		for (i in 0...7) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[7]);
	}

	public function testStcOutputIsBounded() {
		var stc = Stc.classic();
		var prices = [for (i in 0...400) 100.0 + Math.sin(i * 0.2) * 25.0];
		for (v in IndicatorBatch.run(stc, prices)) {
			if (v == null) continue;
			Assert.isTrue(v >= 0.0 && v <= 100.0, 'STC out of [0, 100]: ${v}');
		}
	}

	public function testStcOscillatingSeriesVisitsFullRange() {
		var stc = Stc.classic();
		var prices = [for (i in 0...400) 100.0 + Math.sin(i * 0.15) * 30.0];
		var out = IndicatorBatch.run(stc, prices);
		var sawHigh = false;
		var sawLow = false;
		for (v in out) {
			if (v == null) continue;
			if (v > 80.0) sawHigh = true;
			if (v < 20.0) sawLow = true;
		}
		Assert.isTrue(sawHigh, "STC should reach above 80 on a strong oscillation");
		Assert.isTrue(sawLow, "STC should reach below 20 on a strong oscillation");
	}

	public function testStcBatchEqualsStreaming() {
		var prices = [for (i in 1...201) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = Stc.classic();
		var b = Stc.classic();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testStcResetClearsState() {
		var stc = Stc.classic();
		IndicatorBatch.run(stc, [for (i in 1...201) (i : Float)]);
		Assert.isTrue(stc.isReady());
		stc.reset();
		Assert.isTrue(!stc.isReady());
	}

	// ── Pmo ──────────────────────────────────────────────────────────────────

	public function testPmoRejectsZeroPeriod() {
		try {
			new Pmo(0, 20);
			Assert.fail("Should reject smoothing1 = 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Pmo(35, 0);
			Assert.fail("Should reject smoothing2 = 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPmoRejectsPeriodOne() {
		try {
			new Pmo(1, 20);
			Assert.fail("Should reject smoothing1 = 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Pmo(35, 1);
			Assert.fail("Should reject smoothing2 = 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPmoAccessorsAndMetadata() {
		var pmo = new Pmo(35, 20);
		var p = pmo.periods();
		Assert.equals(35, p.smoothing1);
		Assert.equals(20, p.smoothing2);
		Assert.equals("PMO", pmo.name());
		Assert.isNull(pmo.value());
		pmo.update(100.0);
		pmo.update(101.0);
		Assert.notNull(pmo.value());
	}

	public function testPmoZeroPreviousPriceTreatsRocAsFlat() {
		var pmo = new Pmo(2, 2);
		// Seed prev_price = 0.
		Assert.isNull(pmo.update(0.0));
		// Next bar: prev == 0 hits the fallback returning roc = 0.0; the
		// doubly-smoothed PMO seeds at 0.0 (10 * 0 = 0 through both EMAs).
		var out = pmo.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out);
	}

	public function testPmoFirstEmissionAtSecondUpdate() {
		var pmo = new Pmo(35, 20);
		Assert.equals(2, pmo.warmupPeriod());
		Assert.isNull(pmo.update(100.0));
		Assert.notNull(pmo.update(101.0));
	}

	public function testPmoConstantSeriesYieldsZero() {
		// Flat prices -> ROC is always 0 -> both smoothings stay at 0.
		var pmo = new Pmo(35, 20);
		var out = IndicatorBatch.run(pmo, [for (_ in 0...60) 100.0]);
		for (i in 2...out.length) {
			if (out[i] == null) continue;
			Assert.floatEquals(0.0, out[i], 1e-12);
		}
	}

	public function testPmoSteadyUptrendIsPositive() {
		var pmo = new Pmo(35, 20);
		var prices = [for (i in 1...121) 100.0 * Math.pow(1.01, i)];
		var out = IndicatorBatch.run(pmo, prices);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.isTrue(last > 0.0, 'steady uptrend PMO should be positive, got ${last}');
	}

	public function testPmoIgnoresNonFiniteInput() {
		var pmo = new Pmo(35, 20);
		var out = IndicatorBatch.run(pmo, [for (i in 1...61) (i : Float)]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(last, pmo.update(Math.NaN));
		Assert.floatEquals(last, pmo.update(Math.POSITIVE_INFINITY));
	}

	public function testPmoResetClearsState() {
		var pmo = new Pmo(35, 20);
		IndicatorBatch.run(pmo, [for (i in 1...61) (i : Float)]);
		Assert.isTrue(pmo.isReady());
		pmo.reset();
		Assert.isTrue(!pmo.isReady());
		Assert.isNull(pmo.update(1.0));
	}

	public function testPmoBatchEqualsStreaming() {
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.25) * 8.0];
		var a = new Pmo(35, 20);
		var b = new Pmo(35, 20);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── ZeroLagMacd ──────────────────────────────────────────────────────────

	public function testZeroLagMacdRejectsZeroPeriod() {
		var cases = [
			{fast: 0, slow: 26, sig: 9},
			{fast: 12, slow: 0, sig: 9},
			{fast: 12, slow: 26, sig: 0},
		];
		for (c in cases) {
			try {
				new ZeroLagMacd(c.fast, c.slow, c.sig);
				Assert.fail('Should reject (${c.fast}, ${c.slow}, ${c.sig})');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testZeroLagMacdRejectsFastGeqSlow() {
		try {
			new ZeroLagMacd(26, 12, 9);
			Assert.fail("Should reject fast >= slow");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testZeroLagMacdAccessorsAndMetadata() {
		var z = ZeroLagMacd.classic();
		var p = z.periods();
		Assert.equals(12, p.fast);
		Assert.equals(26, p.slow);
		Assert.equals(9, p.signal);
		Assert.equals("ZeroLagMACD", z.name());
	}

	public function testZeroLagMacdConstantSeriesConvergesToZero() {
		// Each ZLEMA reproduces a constant, so macd, signal and histogram
		// are all 0 after the slowest branch warms.
		var z = new ZeroLagMacd(3, 5, 3);
		var out = IndicatorBatch.run(z, [for (_ in 0...60) 42.0]);
		var seen = 0;
		var i = out.length - 1;
		while (i >= 0 && seen < 5) {
			if (out[i] != null) {
				Assert.floatEquals(0.0, out[i].macd, 1e-12);
				Assert.floatEquals(0.0, out[i].signal, 1e-12);
				Assert.floatEquals(0.0, out[i].histogram, 1e-12);
				seen++;
			}
			i--;
		}
		Assert.equals(5, seen);
	}

	public function testZeroLagMacdHistogramIsMacdMinusSignal() {
		var z = ZeroLagMacd.classic();
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.2) * 5.0];
		for (v in IndicatorBatch.run(z, prices)) {
			if (v == null) continue;
			Assert.floatEquals(v.macd - v.signal, v.histogram, 1e-12);
		}
	}

	public function testZeroLagMacdBatchEqualsStreaming() {
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = ZeroLagMacd.classic();
		var b = ZeroLagMacd.classic();
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].macd, streamed[i].macd);
				Assert.floatEquals(batched[i].signal, streamed[i].signal);
				Assert.floatEquals(batched[i].histogram, streamed[i].histogram);
			}
		}
	}

	public function testZeroLagMacdResetClearsState() {
		var z = ZeroLagMacd.classic();
		IndicatorBatch.run(z, [for (i in 1...121) (i : Float)]);
		Assert.isTrue(z.isReady());
		z.reset();
		Assert.isTrue(!z.isReady());
	}

	public function testZeroLagMacdWarmupPeriodMatchesZlemaChain() {
		// warmup = zlema_warmup(slow) + zlema_warmup(signal) - 1
		// zlema_warmup(p) = (p - 1) / 2 + p
		// (12, 26, 9): zlema_warmup(26) = 12 + 26 = 38;
		//              zlema_warmup(9)  = 4 + 9 = 13.
		//              warmup = 38 + 13 - 1 = 50.
		var z = new ZeroLagMacd(12, 26, 9);
		Assert.equals(50, z.warmupPeriod());
		// (3, 5, 3): zlema_warmup(5) = 2 + 5 = 7; zlema_warmup(3) = 1 + 3 = 4.
		//            warmup = 7 + 4 - 1 = 10.
		var z2 = new ZeroLagMacd(3, 5, 3);
		Assert.equals(10, z2.warmupPeriod());
	}
}
