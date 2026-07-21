package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.Breakaway;
import musescript.indicators.lib.AutocorrelationPeriodogram;
import musescript.indicators.lib.SuperSmoother;
import musescript.indicators.lib.RoofingFilter;

/**
 * Test batch 27: Breakaway, SuperSmoother, RoofingFilter, and AutocorrelationPeriodogram.
 * Known-value cases are transcribed from the Rust fixtures in wickra-core.
 */
class TestPortBatch27 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Breakaway ──────────────────────────────────────────────────────────────

	public function testBreakawayBullishIsOne() {
		var t = new Breakaway();
		Assert.equals(0.0, t.update(bar(20.0, 20.2, 14.8, 15.0, 1.0, 0)));
		Assert.equals(0.0, t.update(bar(14.0, 14.1, 11.9, 12.0, 1.0, 1)));
		Assert.equals(0.0, t.update(bar(12.5, 13.0, 10.5, 11.0, 1.0, 2)));
		Assert.equals(0.0, t.update(bar(11.0, 11.5, 9.0, 9.5, 1.0, 3)));
		Assert.equals(1.0, t.update(bar(9.5, 14.7, 9.4, 14.5, 1.0, 4)));
	}

	public function testBreakawayBearishIsMinusOne() {
		var t = new Breakaway();
		Assert.equals(0.0, t.update(bar(15.0, 20.2, 14.8, 20.0, 1.0, 0)));
		Assert.equals(0.0, t.update(bar(21.0, 23.1, 20.9, 23.0, 1.0, 1)));
		Assert.equals(0.0, t.update(bar(22.5, 24.5, 21.5, 24.0, 1.0, 2)));
		Assert.equals(0.0, t.update(bar(24.0, 26.5, 23.0, 26.0, 1.0, 3)));
		Assert.equals(-1.0, t.update(bar(27.0, 27.2, 20.4, 20.5, 1.0, 4)));
	}

	public function testBreakawayNoBodyGapYieldsZero() {
		var t = new Breakaway();
		// bar2 does not gap below bar1's body (bar2.open >= bar1.close).
		t.update(bar(20.0, 20.2, 14.8, 15.0, 1.0, 0));
		t.update(bar(16.0, 16.1, 13.9, 14.0, 1.0, 1));
		t.update(bar(13.5, 14.0, 11.5, 12.0, 1.0, 2));
		t.update(bar(12.0, 12.5, 10.0, 10.5, 1.0, 3));
		Assert.equals(0.0, t.update(bar(10.5, 15.7, 10.4, 15.5, 1.0, 4)));
	}

	public function testBreakawayBatchEqualsStreaming() {
		var candles:Array<Bar> = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 0.5, base + 1.5, 1.0, i);
		}];
		var a = new Breakaway(), b = new Breakaway();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	public function testBreakawayResetClearsState() {
		var t = new Breakaway();
		t.update(bar(20.0, 20.2, 14.8, 15.0, 1.0, 0));
		t.update(bar(14.0, 14.1, 11.9, 12.0, 1.0, 1));
		t.update(bar(12.5, 13.0, 10.5, 11.0, 1.0, 2));
		t.update(bar(11.0, 11.5, 9.0, 9.5, 1.0, 3));
		t.update(bar(9.5, 14.7, 9.4, 14.5, 1.0, 4));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isFalse(t.isReady());
		Assert.equals(0.0, t.update(bar(20.0, 20.2, 14.8, 15.0, 1.0, 0)));
	}

	// ── AutocorrelationPeriodogram ─────────────────────────────────────────────

	public function testAutocorrelationPeriodogramRejectsInvalidPeriods() {
		// Test that invalid period combinations throw
		try {
			new AutocorrelationPeriodogram(0, 48);
			Assert.fail("Should have thrown for zero period");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new AutocorrelationPeriodogram(3, 48);
			Assert.fail("Should have thrown for min_period < AVG_LENGTH + 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new AutocorrelationPeriodogram(48, 10);
			Assert.fail("Should have thrown for max_period <= min_period");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testAutocorrelationPeriodogramAccessorsAndMetadata() {
		var p = new AutocorrelationPeriodogram(10, 48);
		Assert.equals("AutocorrelationPeriodogram", p.name());
		Assert.equals(51, p.warmupPeriod()); // max_period + AVG_LENGTH = 48 + 3
		Assert.isFalse(p.isReady());
	}

	public function testAutocorrelationPeriodogramFirstEmissionAtWarmupPeriod() {
		var p = new AutocorrelationPeriodogram(8, 20);
		var xs:Array<Float> = [for (i in 0...40) 100.0 + Math.sin(i * 2 * Math.PI / 12.0) * 5.0];
		var out = IndicatorBatch.run(p, xs);
		var warmup = p.warmupPeriod(); // 23
		Assert.equals(23, warmup);
		for (i in 0...warmup - 1) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[warmup - 1]);
	}

	public function testAutocorrelationPeriodogramOutputWithinPeriodBand() {
		var p = new AutocorrelationPeriodogram(10, 48);
		var xs:Array<Float> = [for (i in 0...400) 100.0 + Math.sin(i * 2 * Math.PI / 20.0) * 5.0];
		for (v in IndicatorBatch.run(p, xs)) {
			if (v != null) {
				Assert.isTrue(v >= 10.0 && v <= 48.0, "cycle out of band: " + v);
			}
		}
	}

	public function testAutocorrelationPeriodogramDetectsInjectedCycle() {
		// A clean 20-bar sine: the dominant cycle estimate should settle near 20.
		var p = new AutocorrelationPeriodogram(10, 48);
		var xs:Array<Float> = [for (i in 0...600) 100.0 + Math.sin(i * 2 * Math.PI / 20.0) * 5.0];
		var out = IndicatorBatch.run(p, xs);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.isTrue(Math.abs(last - 20.0) < 6.0, "expected ~20-bar cycle, got " + last);
	}

	public function testAutocorrelationPeriodogramIgnoresNonFinite() {
		var p = new AutocorrelationPeriodogram(10, 48);
		var xs:Array<Float> = [for (i in 0...80) 100.0 + Math.sin(i * 2 * Math.PI / 20.0) * 5.0];
		IndicatorBatch.run(p, xs);
		var before = p.update(Math.NaN);
		var afterNaN = p.update(Math.NaN);
		// Non-finite input should return the previous value
		Assert.equals(before, afterNaN);
	}

	public function testAutocorrelationPeriodogramResetClearsState() {
		var p = new AutocorrelationPeriodogram(10, 48);
		var xs:Array<Float> = [for (i in 0...120) 100.0 + Math.sin(i * 2 * Math.PI / 20.0) * 5.0];
		IndicatorBatch.run(p, xs);
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isFalse(p.isReady());
	}

	public function testAutocorrelationPeriodogramBatchEqualsStreaming() {
		var xs:Array<Float> = [for (i in 0...200) 100.0 + Math.sin(i * 2 * Math.PI / 20.0) * 5.0];
		var batch = IndicatorBatch.run(new AutocorrelationPeriodogram(10, 48), xs);
		var b = new AutocorrelationPeriodogram(10, 48);
		var streamed:Array<Null<Float>> = [for (x in xs) b.update(x)];
		Assert.equals(batch.length, streamed.length);
		for (i in 0...batch.length) {
			if (batch[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batch[i], streamed[i]);
			}
		}
	}

	public function testAutocorrelationPeriodogramFlatInputFallsBackToMinPeriod() {
		// Constant input has zero variance, so the dominant cycle defaults to min_period.
		var flat:Array<Float> = [for (_ in 0...200) 100.0];
		var p = new AutocorrelationPeriodogram(10, 48);
		var out = IndicatorBatch.run(p, flat);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.floatEquals(10.0, last);
	}

	// ── SuperSmoother (helper) ─────────────────────────────────────────────────

	public function testSuperSmootherConstantSeriesConvergesToConstant() {
		// Steady-state gain is 1, so a flat input yields a flat output after warmup.
		var ss = new SuperSmoother(20);
		var out = IndicatorBatch.run(ss, [for (_ in 0...200) 50.0]);
		for (i in 50...out.length) {
			Assert.floatEquals(50.0, out[i], 1e-9);
		}
	}

	public function testSuperSmootherBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 0...120) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = new SuperSmoother(15), b = new SuperSmoother(15);
		var batch = IndicatorBatch.run(a, prices);
		var streamed:Array<Null<Float>> = [for (p in prices) b.update(p)];
		Assert.equals(batch.length, streamed.length);
		for (i in 0...batch.length) {
			if (batch[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batch[i], streamed[i]);
			}
		}
	}

	// ── RoofingFilter (helper) ─────────────────────────────────────────────────

	public function testRoofingFilterConstantSeriesConvergesToZero() {
		// High-pass on a flat input is zero, and the smoother of zero is zero.
		var rf = new RoofingFilter(10, 48);
		var out = IndicatorBatch.run(rf, [for (_ in 0...300) 42.0]);
		for (i in 100...out.length) {
			Assert.floatEquals(0.0, out[i], 1e-6);
		}
	}

	public function testRoofingFilterBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 0...200) 100.0 + Math.sin(i * 0.15) * 5.0];
		var a = new RoofingFilter(10, 48), b = new RoofingFilter(10, 48);
		var batch = IndicatorBatch.run(a, prices);
		var streamed:Array<Null<Float>> = [for (p in prices) b.update(p)];
		Assert.equals(batch.length, streamed.length);
		for (i in 0...batch.length) {
			if (batch[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batch[i], streamed[i]);
			}
		}
	}

	public function testRoofingFilterIgnoresNonFiniteInput() {
		var rf = new RoofingFilter(10, 48);
		var out = IndicatorBatch.run(rf, [for (i in 1...101) (i : Float)]);
		var before = rf.update(Math.NaN);
		Assert.equals(before, rf.update(Math.NaN));
	}

	public function testRoofingFilterResetClearsState() {
		var rf = new RoofingFilter(10, 48);
		IndicatorBatch.run(rf, [for (i in 1...101) (i : Float)]);
		Assert.isTrue(rf.isReady());
		rf.reset();
		Assert.isFalse(rf.isReady());
	}
}
