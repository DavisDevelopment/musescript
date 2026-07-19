package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 10: 10 indicators (force_index, elder_impulse, evening_doji_star,
 * fisher_transform, fisher_rsi, fibonacci_pivots, fib_retracement,
 * gain_loss_ratio, chande_kroll_stop, frama) — standard published formulas
 * (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch10 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── ForceIndex ────────────────────────────────────────────────────────

	public function testForceIndexZeroOnFlatPrice() {
		var f = new ForceIndex(5);
		var out = null;
		for (i in 0...10) out = f.update(bar(10.0, 10.0, 10.0, 10.0, 100.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testForceIndexPositiveOnRisingPriceRisingVolume() {
		var f = new ForceIndex(5);
		var out = null;
		for (i in 0...10) out = f.update(bar(100.0 + i, 100.0 + i, 100.0 + i, 100.0 + i, 100.0));
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── ElderImpulse ──────────────────────────────────────────────────────

	public function testElderImpulseBullishOnAcceleratingUptrend() {
		// A perfectly LINEAR (constant-slope) series is degenerate for a
		// MACD-histogram-based signal: MACD histogram measures the CURVATURE
		// of the fast-vs-slow EMA spread, and a straight line has zero
		// curvature once EMA transients decay, so its histogram collapses to
		// ~0 and Elder Impulse reads neutral forever (verified numerically,
		// not a bug). An accelerating (compounding) trend has real positive
		// curvature and sustains a genuine bullish read.
		var e = new ElderImpulse(5, 3, 6, 2);
		var out = null;
		var price = 100.0;
		for (i in 0...20) { price *= 1.02; out = e.update(price); }
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	public function testElderImpulseBearishOnAcceleratingDowntrend() {
		var e = new ElderImpulse(5, 3, 6, 2);
		var out = null;
		var price = 100.0;
		for (i in 0...20) { price *= 0.98; out = e.update(price); }
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out, 1e-9);
	}

	// ── EveningDojiStar ───────────────────────────────────────────────────

	public function testEveningDojiStarBearish() {
		var e = new EveningDojiStar();
		e.update(bar(9.0, 10.6, 8.9, 10.5, 1.0)); // green bar1: open 9, close 10.5
		e.update(bar(11.0, 11.1, 10.9, 11.005, 1.0)); // gapped-up doji (low 10.9 > 10.5)
		var out = e.update(bar(10.8, 10.85, 9.3, 9.4, 1.0)); // gaps down (high 10.85 < 10.9), closes below bar1 mid (9.75)
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── FisherTransform / FisherRsi ───────────────────────────────────────

	public function testFisherTransformZeroOnFlatSeries() {
		var f = new FisherTransform(10);
		var out = null;
		for (i in 0...20) out = f.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testFisherTransformBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new FisherTransform(10), b = new FisherTransform(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	public function testFisherRsiBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new FisherRsi(14, 10), b = new FisherRsi(14, 10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── FibonacciPivots ───────────────────────────────────────────────────

	public function testFibonacciPivotsReferenceValues() {
		// prev bar: H=12, L=8 (range=4), C=11 -> pivot = 31/3.
		var fp = new FibonacciPivots();
		fp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		var out = fp.update(bar(11.0, 13.0, 10.0, 12.0, 1.0));
		Assert.notNull(out);
		var pivot = (12.0 + 8.0 + 11.0) / 3.0;
		Assert.floatEquals(pivot, out.pivot, 1e-9);
		Assert.floatEquals(pivot + 0.382 * 4.0, out.r1, 1e-9);
		Assert.floatEquals(pivot - 0.382 * 4.0, out.s1, 1e-9);
		Assert.floatEquals(pivot + 4.0, out.r3, 1e-9);
		Assert.floatEquals(pivot - 4.0, out.s3, 1e-9);
	}

	// ── FibRetracement ────────────────────────────────────────────────────

	public function testFibRetracementReferenceValues() {
		var fr = new FibRetracement(3);
		fr.update(bar(10.0, 20.0, 10.0, 15.0, 1.0));
		fr.update(bar(10.0, 25.0, 5.0, 15.0, 1.0));
		var out = fr.update(bar(10.0, 22.0, 8.0, 15.0, 1.0));
		Assert.notNull(out);
		// window high=25, low=5, range=20.
		Assert.floatEquals(5.0, out.level0, 1e-9);
		Assert.floatEquals(25.0, out.level1000, 1e-9);
		Assert.floatEquals(5.0 + 0.5 * 20.0, out.level500, 1e-9);
	}

	// ── GainLossRatio ─────────────────────────────────────────────────────

	public function testGainLossRatioZeroWhenNoLosses() {
		var g = new GainLossRatio(5);
		var out = null;
		for (i in 0...10) out = g.update(100.0 + i);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testGainLossRatioEqualUpDownIsOne() {
		var g = new GainLossRatio(4);
		var out = null;
		var prices = [100.0, 105.0, 100.0, 105.0, 100.0];
		for (p in prices) out = g.update(p);
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	// ── ChandeKrollStop ───────────────────────────────────────────────────

	public function testChandeKrollStopFinite() {
		var cks = new ChandeKrollStop(10, 1.0, 5);
		var out = null;
		for (i in 0...30) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			out = cks.update(bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0));
		}
		Assert.notNull(out);
		Assert.isTrue(Math.isFinite(out.longStop) && Math.isFinite(out.shortStop));
	}

	public function testChandeKrollStopBatchEqualsStreaming() {
		var bars = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0);
		}];
		var a = new ChandeKrollStop(10, 1.0, 5), b = new ChandeKrollStop(10, 1.0, 5);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.floatEquals(batched[i].longStop, streamed[i].longStop, 1e-9);
				Assert.floatEquals(batched[i].shortStop, streamed[i].shortStop, 1e-9);
			}
		}
	}

	// ── Frama ─────────────────────────────────────────────────────────────

	public function testFramaFlatSeriesConvergesToConstant() {
		var f = new Frama(8);
		var out = null;
		for (i in 0...20) out = f.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-9);
	}

	public function testFramaBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new Frama(8), b = new Frama(8);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
