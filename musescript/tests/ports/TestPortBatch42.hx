package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.SharpeRatio;
import musescript.indicators.lib.SortinoRatio;
import musescript.indicators.lib.SterlingRatio;
import musescript.indicators.lib.TailRatio;
import musescript.indicators.lib.TreynorRatio;
import musescript.indicators.lib.UlcerIndex;
import musescript.indicators.lib.UpsidePotentialRatio;
import musescript.indicators.lib.ValueAtRisk;
import musescript.indicators.lib.WinRate;
import musescript.indicators.lib.VolatilityOfVolatility;
import musescript.indicators.lib.TrendLabel;
import musescript.indicators.lib.TrendStrengthIndex;
import musescript.indicators.lib.Tii;
import musescript.indicators.lib.Tsi;
import musescript.indicators.lib.Tsf;
import musescript.indicators.lib.TsfOscillator;
import musescript.indicators.lib.WavePm;
import musescript.indicators.lib.HasbrouckInformationShare;

/**
 * Batch 42: 18 indicators ported from wickra-core (risk/performance ratios &
 * trend metrics). Known-value cases transcribed directly from the Rust
 * fixture blocks; batch_equals_streaming verifies IndicatorBatch.run equals
 * streaming updates.
 */
class TestPortBatch42 extends Test {
	static function assertSame(batched:Array<Null<Float>>, streamed:Array<Null<Float>>) {
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	static function lastNonNull(outs:Array<Null<Float>>):Null<Float> {
		var last:Null<Float> = null;
		for (v in outs) if (v != null) last = v;
		return last;
	}

	// ── SharpeRatio ──────────────────────────────────────────────────────────

	public function testSharpeRatioRejectsPeriodLessThanTwo() {
		try {
			new SharpeRatio(1, 0.0);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new SharpeRatio(0, 0.0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testSharpeRatioAccessorsAndMetadata() {
		var sr = new SharpeRatio(20, 0.001);
		Assert.equals("SharpeRatio", sr.name());
		Assert.equals(20, sr.warmupPeriod());
		Assert.isTrue(!sr.isReady());
	}

	public function testSharpeRatioConstantReturnsYieldZero() {
		var sr = new SharpeRatio(5, 0.0);
		var out = IndicatorBatch.run(sr, [for (_ in 0...10) 0.01]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testSharpeRatioReferenceValue() {
		// returns = [0.01, 0.02, 0.03, 0.04], rf = 0.
		// mean = 0.025, var = 0.00016666..., Sharpe ≈ 1.936491673.
		var sr = new SharpeRatio(4, 0.0);
		var out = IndicatorBatch.run(sr, [0.01, 0.02, 0.03, 0.04]);
		var expected = 0.025 / Math.sqrt(0.00016666666666666667);
		Assert.floatEquals(expected, out[3]);
	}

	public function testSharpeRatioIgnoresNonFiniteInput() {
		var sr = new SharpeRatio(3, 0.0);
		Assert.isNull(sr.update(0.01));
		Assert.isNull(sr.update(Math.NaN));
		Assert.isNull(sr.update(0.02));
		Assert.notNull(sr.update(0.03));
	}

	public function testSharpeRatioWarmupReturnsNone() {
		var sr = new SharpeRatio(5, 0.0);
		for (i in 0...4) Assert.isNull(sr.update(i * 0.01));
		Assert.notNull(sr.update(0.05));
	}

	public function testSharpeRatioResetClearsState() {
		var sr = new SharpeRatio(3, 0.0);
		IndicatorBatch.run(sr, [0.01, 0.02, 0.03]);
		Assert.isTrue(sr.isReady());
		sr.reset();
		Assert.isTrue(!sr.isReady());
		Assert.isNull(sr.update(0.01));
	}

	public function testSharpeRatioBatchEqualsStreaming() {
		var returns = [for (i in 0...50) 0.001 + Math.sin(i * 0.2) * 0.01];
		var a = new SharpeRatio(10, 0.0);
		var b = new SharpeRatio(10, 0.0);
		assertSame(IndicatorBatch.run(a, returns), [for (r in returns) b.update(r)]);
	}

	// ── SortinoRatio ─────────────────────────────────────────────────────────

	public function testSortinoRatioRejectsPeriodLessThanTwo() {
		try {
			new SortinoRatio(1, 0.0);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testSortinoRatioAccessorsAndMetadata() {
		var s = new SortinoRatio(10, 0.001);
		Assert.equals("SortinoRatio", s.name());
		Assert.equals(10, s.warmupPeriod());
		Assert.isTrue(!s.isReady());
	}

	public function testSortinoRatioAllReturnsAboveMarYieldsZeroDownside() {
		var s = new SortinoRatio(5, 0.0);
		var out = IndicatorBatch.run(s, [0.01, 0.02, 0.03, 0.04, 0.05]);
		Assert.floatEquals(0.0, out[4]);
	}

	public function testSortinoRatioReferenceValue() {
		// returns = [-0.02, 0.01, -0.01, 0.03], mar = 0.
		// mean = 0.0025, downside_dev = sqrt(0.000125), Sortino ≈ 0.2236068.
		var s = new SortinoRatio(4, 0.0);
		var out = IndicatorBatch.run(s, [-0.02, 0.01, -0.01, 0.03]);
		var expected = 0.0025 / Math.sqrt(0.000125);
		Assert.floatEquals(expected, out[3]);
	}

	public function testSortinoRatioIgnoresNonFiniteInput() {
		var s = new SortinoRatio(3, 0.0);
		Assert.isNull(s.update(Math.NaN));
		Assert.isNull(s.update(Math.POSITIVE_INFINITY));
	}

	public function testSortinoRatioResetClearsState() {
		var s = new SortinoRatio(3, 0.0);
		IndicatorBatch.run(s, [-0.01, -0.02, -0.005]);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(0.01));
	}

	public function testSortinoRatioBatchEqualsStreaming() {
		var returns = [for (i in 0...50) 0.001 + Math.sin(i * 0.3) * 0.02];
		var a = new SortinoRatio(10, 0.0);
		var b = new SortinoRatio(10, 0.0);
		assertSame(IndicatorBatch.run(a, returns), [for (r in returns) b.update(r)]);
	}

	// ── SterlingRatio ────────────────────────────────────────────────────────

	public function testSterlingRatioRejectsPeriodLessThanTwo() {
		try {
			new SterlingRatio(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testSterlingRatioAccessorsAndMetadata() {
		var sr = new SterlingRatio(12);
		Assert.equals(12, sr.warmupPeriod());
		Assert.equals("SterlingRatio", sr.name());
		Assert.isTrue(!sr.isReady());
	}

	public function testSterlingRatioReferenceValue() {
		// returns [0.1, -0.1, 0.1]: equity 1.1, 0.99, 1.089; peak stays 1.1.
		// dd = [0, 0.1, 0.01]; Sterling = (0.1/3) / (0.11/3) = 0.1/0.11.
		var sr = new SterlingRatio(3);
		var out = IndicatorBatch.run(sr, [0.1, -0.1, 0.1]);
		Assert.floatEquals(0.1 / 0.11, out[2]);
	}

	public function testSterlingRatioNoDrawdownIsZero() {
		var sr = new SterlingRatio(3);
		var last = lastNonNull(IndicatorBatch.run(sr, [0.01, 0.02, 0.03]));
		Assert.floatEquals(0.0, last);
	}

	public function testSterlingRatioLosingWindowIsNegative() {
		var sr = new SterlingRatio(3);
		var last = lastNonNull(IndicatorBatch.run(sr, [-0.05, -0.02, -0.03]));
		Assert.isTrue(last < 0.0);
	}

	public function testSterlingRatioIgnoresNonFiniteInput() {
		var sr = new SterlingRatio(3);
		Assert.isNull(sr.update(0.1));
		Assert.isNull(sr.update(Math.NaN));
		Assert.isNull(sr.update(-0.1));
		Assert.notNull(sr.update(0.1));
	}

	public function testSterlingRatioResetClearsState() {
		var sr = new SterlingRatio(3);
		IndicatorBatch.run(sr, [0.1, -0.1, 0.1]);
		Assert.isTrue(sr.isReady());
		sr.reset();
		Assert.isTrue(!sr.isReady());
		Assert.isNull(sr.update(0.1));
	}

	public function testSterlingRatioBatchEqualsStreaming() {
		var rets = [for (i in 0...60) Math.sin(i * 0.25) * 0.05];
		var a = new SterlingRatio(12);
		var b = new SterlingRatio(12);
		assertSame(IndicatorBatch.run(a, rets), [for (r in rets) b.update(r)]);
	}

	// ── TailRatio ────────────────────────────────────────────────────────────

	public function testTailRatioRejectsPeriodLessThanTwo() {
		try {
			new TailRatio(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new TailRatio(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTailRatioAccessorsAndMetadata() {
		var tr = new TailRatio(20);
		Assert.equals(20, tr.warmupPeriod());
		Assert.equals("TailRatio", tr.name());
		Assert.isTrue(!tr.isReady());
	}

	public function testTailRatioReferenceValue() {
		// sorted window [-0.04, -0.02, 0.0, 0.02, 0.04]:
		// P95 = 0.036, P5 = -0.036 → ratio = 1.0.
		var tr = new TailRatio(5);
		var out = IndicatorBatch.run(tr, [-0.04, -0.02, 0.0, 0.02, 0.04]);
		Assert.floatEquals(1.0, out[4]);
	}

	public function testTailRatioFatterRightTailExceedsOne() {
		var tr = new TailRatio(5);
		var out = IndicatorBatch.run(tr, [-0.01, 0.0, 0.01, 0.02, 0.10]);
		Assert.isTrue(out[4] > 1.0);
	}

	public function testTailRatioFlatWindowIsZero() {
		var tr = new TailRatio(4);
		var last = lastNonNull(IndicatorBatch.run(tr, [0.0, 0.0, 0.0, 0.0]));
		Assert.floatEquals(0.0, last);
	}

	public function testTailRatioIgnoresNonFiniteInput() {
		var tr = new TailRatio(3);
		Assert.isNull(tr.update(0.01));
		Assert.isNull(tr.update(Math.NaN));
		Assert.isNull(tr.update(0.02));
		Assert.notNull(tr.update(0.03));
	}

	public function testTailRatioResetClearsState() {
		var tr = new TailRatio(3);
		IndicatorBatch.run(tr, [-0.01, 0.0, 0.02]);
		Assert.isTrue(tr.isReady());
		tr.reset();
		Assert.isTrue(!tr.isReady());
		Assert.isNull(tr.update(0.01));
	}

	public function testTailRatioBatchEqualsStreaming() {
		var rets = [for (i in 0...60) Math.sin(i * 0.25) * 0.02];
		var a = new TailRatio(15);
		var b = new TailRatio(15);
		assertSame(IndicatorBatch.run(a, rets), [for (r in rets) b.update(r)]);
	}

	// ── TreynorRatio ─────────────────────────────────────────────────────────

	public function testTreynorRatioRejectsPeriodLessThanTwo() {
		try {
			new TreynorRatio(1, 0.0);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTreynorRatioAccessorsAndMetadata() {
		var t = new TreynorRatio(20, 0.001);
		Assert.equals("TreynorRatio", t.name());
		Assert.equals(20, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testTreynorRatioReferenceBetaTwoPayoff() {
		// a_i = 2 * b_i with non-zero mean: Beta = 2, Treynor = mean_b.
		var t = new TreynorRatio(20, 0.0);
		var inputs = [for (i in 1...21) { a: 2.0 * i * 0.01, b: i * 0.01 }];
		var out = IndicatorBatch.run(t, inputs);
		var sumB = 0.0;
		for (p in inputs) sumB += p.b;
		Assert.floatEquals(sumB / 20.0, out[19]);
	}

	public function testTreynorRatioFlatBenchmarkYieldsZero() {
		var t = new TreynorRatio(4, 0.0);
		var out = IndicatorBatch.run(t, [{a: 0.01, b: 0.0}, {a: 0.02, b: 0.0}, {a: -0.01, b: 0.0}, {a: 0.03, b: 0.0}]);
		Assert.floatEquals(0.0, out[3]);
	}

	public function testTreynorRatioZeroBetaReturnsZero() {
		// Constant asset returns vs varying benchmark force cov(a,b) = 0.
		var t = new TreynorRatio(4, 0.0);
		var pairs = [{a: 0.01, b: 0.005}, {a: 0.01, b: -0.002}, {a: 0.01, b: 0.001}, {a: 0.01, b: 0.003}];
		var last:Null<Float> = null;
		for (p in pairs) last = t.update(p);
		Assert.floatEquals(0.0, last);
	}

	public function testTreynorRatioIgnoresNonFiniteInput() {
		var t = new TreynorRatio(3, 0.0);
		Assert.isNull(t.update({a: Math.NaN, b: 0.0}));
		Assert.isNull(t.update({a: 0.0, b: Math.POSITIVE_INFINITY}));
	}

	public function testTreynorRatioResetClearsState() {
		var t = new TreynorRatio(3, 0.0);
		IndicatorBatch.run(t, [{a: 0.01, b: 0.005}, {a: 0.02, b: 0.01}, {a: -0.01, b: -0.005}]);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.update({a: 0.01, b: 0.005}));
	}

	public function testTreynorRatioBatchEqualsStreaming() {
		var inputs = [for (i in 0...50) {
			var b = Math.sin(i * 0.2) * 0.01;
			{ a: 1.5 * b + 0.001, b: b };
		}];
		var a = new TreynorRatio(10, 0.0);
		var b = new TreynorRatio(10, 0.0);
		assertSame(IndicatorBatch.run(a, inputs), [for (x in inputs) b.update(x)]);
	}

	// ── UlcerIndex ───────────────────────────────────────────────────────────

	public function testUlcerIndexRejectsZeroPeriod() {
		try {
			new UlcerIndex(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testUlcerIndexAccessorsAndMetadata() {
		var ui = new UlcerIndex(14);
		Assert.equals("UlcerIndex", ui.name());
		Assert.isNull(ui.value());
		// Drive past warmup so value() flips to non-null.
		for (i in 0...ui.warmupPeriod()) ui.update(100.0 + Math.sin(i) * 5.0);
		Assert.notNull(ui.value());
	}

	public function testUlcerIndexZeroMaxPriceYieldsZeroDrawdown() {
		var ui = new UlcerIndex(3);
		var last = lastNonNull(IndicatorBatch.run(ui, [for (_ in 0...10) 0.0]));
		Assert.floatEquals(0.0, last);
	}

	public function testUlcerIndexReferenceValues() {
		// UlcerIndex(2): warmup = 3. [10, 8, 12, 9]:
		//   bar 3 -> UI = sqrt(200); bar 4 -> UI = sqrt(312.5).
		var ui = new UlcerIndex(2);
		var out = IndicatorBatch.run(ui, [10.0, 8.0, 12.0, 9.0]);
		Assert.equals(3, ui.warmupPeriod());
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(Math.sqrt(200.0), out[2]);
		Assert.floatEquals(Math.sqrt(312.5), out[3]);
	}

	public function testUlcerIndexPureUptrendYieldsZero() {
		var ui = new UlcerIndex(5);
		var out = IndicatorBatch.run(ui, [for (i in 1...41) (i : Float)]);
		for (i in (ui.warmupPeriod() - 1)...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testUlcerIndexConstantSeriesYieldsZero() {
		var ui = new UlcerIndex(5);
		var out = IndicatorBatch.run(ui, [for (_ in 0...30) 50.0]);
		for (i in (ui.warmupPeriod() - 1)...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testUlcerIndexIgnoresNonFiniteInput() {
		var ui = new UlcerIndex(2);
		var out = IndicatorBatch.run(ui, [10.0, 8.0, 12.0, 9.0]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.equals(last, ui.update(Math.NaN));
		Assert.equals(last, ui.update(Math.POSITIVE_INFINITY));
	}

	public function testUlcerIndexResetClearsState() {
		var ui = new UlcerIndex(3);
		IndicatorBatch.run(ui, [10.0, 8.0, 12.0, 9.0, 11.0, 7.0]);
		Assert.isTrue(ui.isReady());
		ui.reset();
		Assert.isTrue(!ui.isReady());
		Assert.isNull(ui.update(10.0));
	}

	public function testUlcerIndexBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 10.0];
		var a = new UlcerIndex(14);
		var b = new UlcerIndex(14);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── UpsidePotentialRatio ─────────────────────────────────────────────────

	public function testUpsidePotentialRatioRejectsPeriodLessThanTwo() {
		try {
			new UpsidePotentialRatio(1, 0.0);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testUpsidePotentialRatioRejectsNonFiniteMar() {
		try {
			new UpsidePotentialRatio(10, Math.NaN);
			Assert.fail("Should reject non-finite mar");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testUpsidePotentialRatioAccessorsAndMetadata() {
		var upr = new UpsidePotentialRatio(20, 0.001);
		Assert.equals(20, upr.warmupPeriod());
		Assert.equals("UpsidePotentialRatio", upr.name());
		Assert.isTrue(!upr.isReady());
	}

	public function testUpsidePotentialRatioReferenceValue() {
		// returns [0.02, -0.01, 0.03, -0.02], mar = 0.
		// upside = 0.0125; downside = sqrt(0.000125); UPR = 0.0125/sqrt(0.000125).
		var upr = new UpsidePotentialRatio(4, 0.0);
		var out = IndicatorBatch.run(upr, [0.02, -0.01, 0.03, -0.02]);
		var expected = 0.0125 / Math.sqrt(0.000125);
		Assert.floatEquals(expected, out[3]);
	}

	public function testUpsidePotentialRatioNoDownsideIsZero() {
		var upr = new UpsidePotentialRatio(3, 0.0);
		var last = lastNonNull(IndicatorBatch.run(upr, [0.01, 0.02, 0.03]));
		Assert.floatEquals(0.0, last);
	}

	public function testUpsidePotentialRatioIgnoresNonFiniteInput() {
		var upr = new UpsidePotentialRatio(3, 0.0);
		Assert.isNull(upr.update(0.01));
		Assert.isNull(upr.update(Math.POSITIVE_INFINITY));
		Assert.isNull(upr.update(-0.02));
		Assert.notNull(upr.update(0.03));
	}

	public function testUpsidePotentialRatioResetClearsState() {
		var upr = new UpsidePotentialRatio(2, 0.0);
		IndicatorBatch.run(upr, [0.02, -0.01]);
		Assert.isTrue(upr.isReady());
		upr.reset();
		Assert.isTrue(!upr.isReady());
		Assert.isNull(upr.update(0.01));
	}

	public function testUpsidePotentialRatioBatchEqualsStreaming() {
		var rets = [for (i in 0...60) Math.sin(i * 0.25) * 0.02];
		var a = new UpsidePotentialRatio(12, 0.0);
		var b = new UpsidePotentialRatio(12, 0.0);
		assertSame(IndicatorBatch.run(a, rets), [for (r in rets) b.update(r)]);
	}

	// ── ValueAtRisk ──────────────────────────────────────────────────────────

	public function testValueAtRiskRejectsInvalidParams() {
		try {
			new ValueAtRisk(1, 0.95);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new ValueAtRisk(20, 0.0);
			Assert.fail("Should reject confidence 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new ValueAtRisk(20, 1.0);
			Assert.fail("Should reject confidence 1");
		} catch (e:Dynamic) Assert.pass();
		try {
			new ValueAtRisk(20, Math.NaN);
			Assert.fail("Should reject NaN confidence");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testValueAtRiskAccessorsAndMetadata() {
		var v = new ValueAtRisk(100, 0.95);
		Assert.equals("ValueAtRisk", v.name());
		Assert.equals(100, v.warmupPeriod());
		Assert.isTrue(!v.isReady());
	}

	public function testValueAtRiskReferenceValue() {
		// returns = -5..4 (each *0.01), confidence 0.95: VaR = 0.0455.
		var v = new ValueAtRisk(10, 0.95);
		var returns = [for (i in -5...5) i * 0.01];
		var out = IndicatorBatch.run(v, returns);
		Assert.floatEquals(0.0455, out[9]);
	}

	public function testValueAtRiskAllPositiveReturnsYieldZero() {
		var v = new ValueAtRisk(5, 0.95);
		var out = IndicatorBatch.run(v, [0.01, 0.02, 0.03, 0.04, 0.05]);
		Assert.floatEquals(0.0, out[4]);
	}

	public function testValueAtRiskIntegerPositionQuantileBranch() {
		// period=5, confidence=0.75 -> q=0.25 -> pos=1.0 (integer);
		// sorted[1] = -0.04, so VaR = 0.04 exactly.
		var v = new ValueAtRisk(5, 0.75);
		var out = IndicatorBatch.run(v, [-0.05, -0.04, -0.03, -0.02, -0.01]);
		Assert.floatEquals(0.04, out[4]);
	}

	public function testValueAtRiskIgnoresNonFiniteInput() {
		var v = new ValueAtRisk(3, 0.95);
		Assert.isNull(v.update(Math.NaN));
		Assert.isNull(v.update(Math.POSITIVE_INFINITY));
	}

	public function testValueAtRiskResetClearsState() {
		var v = new ValueAtRisk(3, 0.95);
		IndicatorBatch.run(v, [-0.01, -0.02, -0.03]);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(0.01));
	}

	public function testValueAtRiskBatchEqualsStreaming() {
		var returns = [for (i in 0...50) Math.sin(i * 0.2) * 0.02];
		var a = new ValueAtRisk(10, 0.95);
		var b = new ValueAtRisk(10, 0.95);
		assertSame(IndicatorBatch.run(a, returns), [for (r in returns) b.update(r)]);
	}

	// ── WinRate ──────────────────────────────────────────────────────────────

	public function testWinRateRejectsZeroPeriod() {
		try {
			new WinRate(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testWinRateAccessorsAndMetadata() {
		var wr = new WinRate(20);
		Assert.equals(20, wr.warmupPeriod());
		Assert.equals("WinRate", wr.name());
		Assert.isTrue(!wr.isReady());
	}

	public function testWinRateReferenceValue() {
		// +, -, +, + -> 3 wins of 4 -> 0.75.
		var wr = new WinRate(4);
		var out = IndicatorBatch.run(wr, [1.0, -1.0, 2.0, 1.0]);
		Assert.floatEquals(0.75, out[3]);
	}

	public function testWinRateAllWinsIsOne() {
		var wr = new WinRate(5);
		var out = IndicatorBatch.run(wr, [for (_ in 0...10) 1.0]);
		for (v in out) if (v != null) Assert.floatEquals(1.0, v);
	}

	public function testWinRateAllLossesIsZero() {
		var wr = new WinRate(5);
		var out = IndicatorBatch.run(wr, [for (_ in 0...10) -1.0]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testWinRateFlatReturnsAreNotWins() {
		// Zeros count as non-wins: 2 wins, 2 flats -> 0.5.
		var wr = new WinRate(4);
		var out = IndicatorBatch.run(wr, [1.0, 0.0, 2.0, 0.0]);
		Assert.floatEquals(0.5, out[3]);
	}

	public function testWinRateRollingWindowDropsOldWins() {
		// period 3: after [+,+,+] -> 1.0, then three losses slide the wins out.
		var wr = new WinRate(3);
		var out = IndicatorBatch.run(wr, [1.0, 1.0, 1.0, -1.0, -1.0, -1.0]);
		Assert.floatEquals(1.0, out[2]);
		Assert.floatEquals(0.0, out[5]);
	}

	public function testWinRateResetClearsState() {
		var wr = new WinRate(5);
		IndicatorBatch.run(wr, [1.0, -1.0, 1.0, -1.0, 1.0]);
		Assert.isTrue(wr.isReady());
		wr.reset();
		Assert.isTrue(!wr.isReady());
		Assert.isNull(wr.update(1.0));
	}

	public function testWinRateBatchEqualsStreaming() {
		var rets = [for (i in 0...60) Math.sin(i * 0.5) * 2.0];
		var a = new WinRate(14);
		var b = new WinRate(14);
		assertSame(IndicatorBatch.run(a, rets), [for (r in rets) b.update(r)]);
	}

	// ── VolatilityOfVolatility ───────────────────────────────────────────────

	public function testVolatilityOfVolatilityRejectsBadWindows() {
		try {
			new VolatilityOfVolatility(0, 10);
			Assert.fail("Should reject zero vol window");
		} catch (e:Dynamic) Assert.pass();
		try {
			new VolatilityOfVolatility(10, 0);
			Assert.fail("Should reject zero vov window");
		} catch (e:Dynamic) Assert.pass();
		try {
			new VolatilityOfVolatility(1, 10);
			Assert.fail("Should reject vol window 1");
		} catch (e:Dynamic) Assert.pass();
		try {
			new VolatilityOfVolatility(10, 1);
			Assert.fail("Should reject vov window 1");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testVolatilityOfVolatilityAccessorsAndMetadata() {
		var vov = new VolatilityOfVolatility(20, 10);
		Assert.equals(30, vov.warmupPeriod());
		Assert.equals("VolatilityOfVolatility", vov.name());
		Assert.isTrue(!vov.isReady());
		Assert.isNull(vov.value());
	}

	public function testVolatilityOfVolatilityFirstEmissionAtWarmupPeriod() {
		var vov = new VolatilityOfVolatility(3, 3);
		var prices = [for (i in 1...21) 100.0 + Math.sin(i * 0.7) * 4.0];
		var out = IndicatorBatch.run(vov, prices);
		var warmup = vov.warmupPeriod(); // 6
		for (i in 0...(warmup - 1)) Assert.isNull(out[i]);
		Assert.notNull(out[warmup - 1]);
	}

	public function testVolatilityOfVolatilityConstantSeriesYieldsZero() {
		var vov = new VolatilityOfVolatility(5, 5);
		var out = IndicatorBatch.run(vov, [for (_ in 0...60) 100.0]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testVolatilityOfVolatilityOutputIsNonNegative() {
		var vov = new VolatilityOfVolatility(10, 10);
		var prices = [for (i in 1...301) 100.0 + Math.sin(i * 0.3) * 12.0];
		var out = IndicatorBatch.run(vov, prices);
		for (v in out) if (v != null) Assert.isTrue(v >= 0.0);
	}

	public function testVolatilityOfVolatilityIgnoresNonFiniteInput() {
		var vov = new VolatilityOfVolatility(3, 3);
		var out = IndicatorBatch.run(vov, [for (i in 1...41) (i : Float)]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.equals(last, vov.update(Math.NaN));
		Assert.equals(last, vov.update(Math.POSITIVE_INFINITY));
	}

	public function testVolatilityOfVolatilitySkipsNonPositivePrices() {
		var vov = new VolatilityOfVolatility(3, 3);
		var warmup = IndicatorBatch.run(vov, [for (i in 1...41) (i : Float)]);
		var baseline = lastNonNull(warmup);
		Assert.notNull(baseline);
		Assert.equals(baseline, vov.update(-5.0));
		Assert.equals(baseline, vov.update(0.0));
	}

	public function testVolatilityOfVolatilityResetClearsState() {
		var vov = new VolatilityOfVolatility(3, 3);
		IndicatorBatch.run(vov, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(vov.isReady());
		vov.reset();
		Assert.isTrue(!vov.isReady());
		Assert.isNull(vov.value());
		Assert.isNull(vov.update(1.0));
	}

	public function testVolatilityOfVolatilityBatchEqualsStreaming() {
		var prices = [for (i in 1...201) 100.0 + Math.sin(i * 0.25) * 9.0];
		var a = new VolatilityOfVolatility(10, 10);
		var b = new VolatilityOfVolatility(10, 10);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── TrendLabel ───────────────────────────────────────────────────────────

	public function testTrendLabelRejectsPeriodBelowTwo() {
		try {
			new TrendLabel(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		var ok = new TrendLabel(2);
		Assert.notNull(ok);
	}

	public function testTrendLabelAccessorsAndMetadata() {
		var tl = new TrendLabel(10);
		Assert.equals(10, tl.warmupPeriod());
		Assert.equals("TrendLabel", tl.name());
		Assert.isTrue(!tl.isReady());
	}

	public function testTrendLabelRisingSeriesIsPlusOne() {
		var tl = new TrendLabel(10);
		var last = lastNonNull(IndicatorBatch.run(tl, [for (i in 0...20) (i : Float)]));
		Assert.floatEquals(1.0, last);
	}

	public function testTrendLabelFallingSeriesIsMinusOne() {
		var tl = new TrendLabel(10);
		var last = lastNonNull(IndicatorBatch.run(tl, [for (i in 0...20) 100.0 - i]));
		Assert.floatEquals(-1.0, last);
	}

	public function testTrendLabelFlatSeriesIsZero() {
		var tl = new TrendLabel(8);
		var out = IndicatorBatch.run(tl, [for (_ in 0...16) 42.0]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testTrendLabelScaleInvariantSign() {
		var prices = [for (i in 0...30) 100.0 + Math.sin(i * 0.4) * 5.0];
		var small = IndicatorBatch.run(new TrendLabel(12), prices);
		var large = IndicatorBatch.run(new TrendLabel(12), [for (p in prices) p * 1000.0]);
		assertSame(small, large);
	}

	public function testTrendLabelOutputIsTernary() {
		var tl = new TrendLabel(14);
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.3) * 10.0];
		var out = IndicatorBatch.run(tl, prices);
		for (v in out) if (v != null) Assert.isTrue(v == -1.0 || v == 0.0 || v == 1.0);
	}

	public function testTrendLabelResetClearsState() {
		var tl = new TrendLabel(5);
		IndicatorBatch.run(tl, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(tl.isReady());
		tl.reset();
		Assert.isTrue(!tl.isReady());
		Assert.isNull(tl.update(1.0));
	}

	public function testTrendLabelBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new TrendLabel(14);
		var b = new TrendLabel(14);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── TrendStrengthIndex ───────────────────────────────────────────────────

	public function testTrendStrengthIndexRejectsInvalidPeriod() {
		try {
			new TrendStrengthIndex(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new TrendStrengthIndex(1);
			Assert.fail("Should reject period 1");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTrendStrengthIndexAccessorsAndMetadata() {
		var tsi = new TrendStrengthIndex(20);
		Assert.equals(20, tsi.warmupPeriod());
		Assert.equals("TrendStrengthIndex", tsi.name());
		Assert.isTrue(!tsi.isReady());
	}

	public function testTrendStrengthIndexWarmupEmitsAtPeriod() {
		var tsi = new TrendStrengthIndex(4);
		var out = IndicatorBatch.run(tsi, [for (i in 0...6) (i : Float)]);
		Assert.isNull(out[2]);
		Assert.notNull(out[3]);
	}

	public function testTrendStrengthIndexPerfectUptrendIsPlusOne() {
		var tsi = new TrendStrengthIndex(10);
		var out = IndicatorBatch.run(tsi, [for (i in 0...10) (i : Float)]);
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testTrendStrengthIndexPerfectDowntrendIsMinusOne() {
		var tsi = new TrendStrengthIndex(10);
		var out = IndicatorBatch.run(tsi, [for (i in 0...10) 100.0 - i]);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testTrendStrengthIndexFlatMarketReturnsZero() {
		var tsi = new TrendStrengthIndex(8);
		var out = IndicatorBatch.run(tsi, [for (_ in 0...12) 42.0]);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testTrendStrengthIndexNoisyTrendIsBetween() {
		// An upward drift with noise: positive but not a perfect fit.
		var tsi = new TrendStrengthIndex(12);
		var inputs = [for (i in 0...12) i + (i % 2 == 0 ? 0.0 : 3.0)];
		var out = IndicatorBatch.run(tsi, inputs);
		var last = out[out.length - 1];
		Assert.isTrue(last > 0.0 && last < 1.0);
	}

	public function testTrendStrengthIndexResetClearsState() {
		var tsi = new TrendStrengthIndex(10);
		IndicatorBatch.run(tsi, [for (i in 0...10) (i : Float)]);
		Assert.isTrue(tsi.isReady());
		tsi.reset();
		Assert.isTrue(!tsi.isReady());
	}

	public function testTrendStrengthIndexBatchEqualsStreaming() {
		var inputs = [for (i in 0...80) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = new TrendStrengthIndex(15);
		var b = new TrendStrengthIndex(15);
		assertSame(IndicatorBatch.run(a, inputs), [for (x in inputs) b.update(x)]);
	}

	// ── Tii ──────────────────────────────────────────────────────────────────

	public function testTiiRejectsZeroPeriod() {
		try {
			new Tii(0, 10);
			Assert.fail("Should reject sma period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new Tii(10, 0);
			Assert.fail("Should reject dev period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTiiAccessorsAndMetadata() {
		var t = new Tii(60, 30);
		Assert.equals(89, t.warmupPeriod());
		Assert.equals("TII", t.name());
		Assert.isNull(t.value());
		for (i in 1...101) t.update(100.0 + i);
		Assert.notNull(t.value());
	}

	public function testTiiFirstEmissionAtWarmupPeriod() {
		var prices = [for (i in 1...31) 100.0 + Math.sin(i * 0.3) * 5.0];
		var t = new Tii(5, 4);
		var out = IndicatorBatch.run(t, prices);
		var warmup = 5 + 4 - 1; // 8
		for (i in 0...(warmup - 1)) Assert.isNull(out[i]);
		Assert.notNull(out[warmup - 1]);
	}

	public function testTiiPureUptrendSaturatesAt100() {
		var prices = [for (i in 1...81) 100.0 + i];
		var t = new Tii(10, 5);
		var last = lastNonNull(IndicatorBatch.run(t, prices));
		Assert.floatEquals(100.0, last);
	}

	public function testTiiPureDowntrendFallsToZero() {
		var prices = [for (i in 0...80) 100.0 + (80 - i)];
		var t = new Tii(10, 5);
		var last = lastNonNull(IndicatorBatch.run(t, prices));
		Assert.floatEquals(0.0, last);
	}

	public function testTiiConstantSeriesYieldsNeutral50() {
		var t = new Tii(5, 4);
		var last = lastNonNull(IndicatorBatch.run(t, [for (_ in 0...30) 10.0]));
		Assert.floatEquals(50.0, last);
	}

	public function testTiiOutputBoundedInUnitInterval() {
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.3) * 6.0 + Math.cos(i * 0.07) * 3.0];
		var t = new Tii(20, 10);
		var out = IndicatorBatch.run(t, prices);
		for (v in out) if (v != null) Assert.isTrue(v >= 0.0 && v <= 100.0);
	}

	public function testTiiResetClearsState() {
		var t = new Tii(5, 4);
		IndicatorBatch.run(t, [for (i in 1...31) (i : Float)]);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.update(1.0));
	}

	public function testTiiBatchEqualsStreaming() {
		var prices = [for (i in 0...120) 100.0 + Math.sin(i * 0.25) * 5.0];
		var a = new Tii(20, 10);
		var b = new Tii(20, 10);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Tsi ──────────────────────────────────────────────────────────────────

	public function testTsiRejectsZeroPeriod() {
		try {
			new Tsi(0, 13);
			Assert.fail("Should reject long period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new Tsi(25, 0);
			Assert.fail("Should reject short period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTsiAccessorsAndMetadata() {
		var tsi = new Tsi(25, 13);
		Assert.equals("TSI", tsi.name());
		Assert.isNull(tsi.value());
		for (i in 1...(tsi.warmupPeriod() + 1)) tsi.update(100.0 + i);
		Assert.notNull(tsi.value());
	}

	public function testTsiFirstEmissionAtWarmupPeriod() {
		var tsi = new Tsi(5, 3);
		Assert.equals(8, tsi.warmupPeriod());
		var out = IndicatorBatch.run(tsi, [for (i in 1...41) (i : Float)]);
		for (i in 0...7) Assert.isNull(out[i]);
		Assert.notNull(out[7]);
	}

	public function testTsiPureUptrendSaturatesAtPlus100() {
		// Every momentum is +1, so |momentum| == momentum and the ratio is 1.
		var tsi = new Tsi(5, 3);
		var out = IndicatorBatch.run(tsi, [for (i in 1...41) (i : Float)]);
		for (i in 8...out.length) {
			if (out[i] != null) Assert.floatEquals(100.0, out[i]);
		}
	}

	public function testTsiPureDowntrendSaturatesAtMinus100() {
		var tsi = new Tsi(5, 3);
		var out = IndicatorBatch.run(tsi, [for (i in 0...40) (40.0 - i)]);
		for (i in 8...out.length) {
			if (out[i] != null) Assert.floatEquals(-100.0, out[i]);
		}
	}

	public function testTsiConstantSeriesYieldsZero() {
		var tsi = new Tsi(5, 3);
		var out = IndicatorBatch.run(tsi, [for (_ in 0...40) 50.0]);
		for (i in 8...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTsiIgnoresNonFiniteInput() {
		var tsi = new Tsi(5, 3);
		var out = IndicatorBatch.run(tsi, [for (i in 1...41) (i : Float)]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.equals(last, tsi.update(Math.NaN));
		Assert.equals(last, tsi.update(Math.POSITIVE_INFINITY));
	}

	public function testTsiResetClearsState() {
		var tsi = new Tsi(5, 3);
		IndicatorBatch.run(tsi, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(tsi.isReady());
		tsi.reset();
		Assert.isTrue(!tsi.isReady());
		Assert.isNull(tsi.update(1.0));
	}

	public function testTsiBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 9.0];
		var a = new Tsi(13, 7);
		var b = new Tsi(13, 7);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Tsf ──────────────────────────────────────────────────────────────────

	public function testTsfRejectsShortPeriod() {
		try {
			new Tsf(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTsfAccessorsReportConfig() {
		var tsf = new Tsf(5);
		Assert.equals("TSF", tsf.name());
		Assert.equals(5, tsf.warmupPeriod());
		Assert.isTrue(!tsf.isReady());
	}

	public function testTsfReferenceValue() {
		// period 3 over [1, 2, 9]: fit y = 0 + 4x, forecast at x = 3 is 12.
		var tsf = new Tsf(3);
		var out = IndicatorBatch.run(tsf, [1.0, 2.0, 9.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(12.0, out[2]);
		Assert.isTrue(tsf.isReady());
	}

	public function testTsfForecastsACleanLineOneStepAhead() {
		// Window [10, 12, 14]: y = 10 + 2x, forecast at x = 3 is 16.
		var tsf = new Tsf(3);
		var out = IndicatorBatch.run(tsf, [1.0, 10.0, 12.0, 14.0]);
		Assert.floatEquals(16.0, out[3]);
	}

	public function testTsfResetClearsState() {
		var tsf = new Tsf(3);
		IndicatorBatch.run(tsf, [1.0, 2.0, 9.0]);
		Assert.isTrue(tsf.isReady());
		tsf.reset();
		Assert.isTrue(!tsf.isReady());
		Assert.isNull(tsf.update(1.0));
	}

	public function testTsfBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new Tsf(14);
		var b = new Tsf(14);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── TsfOscillator ────────────────────────────────────────────────────────

	public function testTsfOscillatorRejectsShortPeriod() {
		try {
			new TsfOscillator(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new TsfOscillator(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testTsfOscillatorAccessorsAndMetadata() {
		var osc = new TsfOscillator(14);
		Assert.equals(14, osc.warmupPeriod());
		Assert.equals("TsfOscillator", osc.name());
		Assert.isTrue(!osc.isReady());
	}

	public function testTsfOscillatorReferenceValue() {
		// period 3 over [1, 2, 9]: one-bar-ahead TSF is 12; close = 9 →
		// TSFOsc = 100·(9 − 12)/9 = −33.3333…%.
		var osc = new TsfOscillator(3);
		var out = IndicatorBatch.run(osc, [1.0, 2.0, 9.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(-100.0 / 3.0, out[2]);
		Assert.isTrue(osc.isReady());
	}

	public function testTsfOscillatorConstantSeriesYieldsZero() {
		var osc = new TsfOscillator(5);
		var out = IndicatorBatch.run(osc, [for (_ in 0...30) 42.0]);
		for (i in 4...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTsfOscillatorLinearUptrendReadsNegative() {
		var osc = new TsfOscillator(5);
		var prices = [for (i in 1...21) i * 2.0];
		var out = IndicatorBatch.run(osc, prices);
		for (i in 4...out.length) {
			if (out[i] != null) Assert.isTrue(out[i] < 0.0);
		}
	}

	public function testTsfOscillatorWarmupEmitsFirstValueAtPeriod() {
		var osc = new TsfOscillator(3);
		Assert.isNull(osc.update(1.0));
		Assert.isNull(osc.update(2.0));
		Assert.notNull(osc.update(3.0));
	}

	public function testTsfOscillatorZeroCloseHoldsValue() {
		var osc = new TsfOscillator(3);
		var out = IndicatorBatch.run(osc, [1.0, 2.0, 3.0]);
		var before = out[2];
		Assert.equals(before, osc.update(0.0));
	}

	public function testTsfOscillatorResetClearsState() {
		var osc = new TsfOscillator(5);
		IndicatorBatch.run(osc, [for (i in 1...21) (i : Float)]);
		Assert.isTrue(osc.isReady());
		osc.reset();
		Assert.isTrue(!osc.isReady());
		Assert.isNull(osc.update(1.0));
	}

	public function testTsfOscillatorBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new TsfOscillator(14);
		var b = new TsfOscillator(14);
		assertSame(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── WavePm ───────────────────────────────────────────────────────────────

	public function testWavePmRejectsZeroPeriod() {
		try {
			new WavePm(0, 3);
			Assert.fail("Should reject length 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new WavePm(10, 0);
			Assert.fail("Should reject smoothing 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testWavePmAccessorsAndMetadata() {
		var w = new WavePm(10, 3);
		// 2*10 + 3 - 1 = 22.
		Assert.equals(22, w.warmupPeriod());
		Assert.equals("WavePm", w.name());
		Assert.isTrue(!w.isReady());
	}

	public function testWavePmWarmupEmitsAtExpectedBar() {
		var w = new WavePm(3, 2);
		// warmup = 2*3 + 2 - 1 = 7 -> first value at input 7 (index 6).
		var out = IndicatorBatch.run(w, [for (i in 0...12) (i : Float)]);
		Assert.isNull(out[5]);
		Assert.notNull(out[6]);
	}

	public function testWavePmFlatMarketReadsZero() {
		var w = new WavePm(4, 2);
		var out = IndicatorBatch.run(w, [for (_ in 0...20) 50.0]);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testWavePmSteadyTrendReadsBaseline() {
		// Constant-slope ramp pins to the baseline 100*(1 - e^-0.5).
		var w = new WavePm(10, 3);
		var out = IndicatorBatch.run(w, [for (i in 0...60) i * 5.0]);
		var baseline = 100.0 * (1.0 - Math.exp(-0.5));
		Assert.floatEquals(baseline, out[out.length - 1]);
	}

	public function testWavePmAccelerationReadsAboveBaseline() {
		// A quadratic path: momentum keeps outrunning its lagged energy.
		var w = new WavePm(10, 3);
		var out = IndicatorBatch.run(w, [for (i in 0...60) (i * i) * 0.1]);
		var last = out[out.length - 1];
		var baseline = 100.0 * (1.0 - Math.exp(-0.5));
		Assert.isTrue(last > baseline);
		Assert.isTrue(last <= 100.0);
	}

	public function testWavePmResetClearsState() {
		var w = new WavePm(10, 3);
		IndicatorBatch.run(w, [for (i in 0...60) i * 5.0]);
		Assert.isTrue(w.isReady());
		w.reset();
		Assert.isTrue(!w.isReady());
	}

	public function testWavePmBatchEqualsStreaming() {
		var inputs = [for (i in 0...80) 100.0 + Math.sin(i * 0.2) * 5.0];
		var a = new WavePm(10, 3);
		var b = new WavePm(10, 3);
		assertSame(IndicatorBatch.run(a, inputs), [for (x in inputs) b.update(x)]);
	}

	// ── HasbrouckInformationShare ────────────────────────────────────────────

	public function testHasbrouckRejectsPeriodBelowTwo() {
		try {
			new HasbrouckInformationShare(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) Assert.pass();
		var ok = new HasbrouckInformationShare(2);
		Assert.notNull(ok);
	}

	public function testHasbrouckAccessorsAndMetadata() {
		var h = new HasbrouckInformationShare(20);
		Assert.equals(21, h.warmupPeriod());
		Assert.equals("HasbrouckInformationShare", h.name());
		Assert.isTrue(!h.isReady());
	}

	public function testHasbrouckWarmupNeedsPeriodPlusOne() {
		var h = new HasbrouckInformationShare(3);
		Assert.isNull(h.update({a: 1.0, b: 1.0}));
		Assert.isNull(h.update({a: 2.0, b: 2.0}));
		Assert.isNull(h.update({a: 3.0, b: 2.5}));
		Assert.notNull(h.update({a: 4.0, b: 3.0}));
	}

	public function testHasbrouckLoudVenueLeads() {
		// x is far more volatile than y -> x holds nearly all the share.
		var pairs = [for (i in 0...40) {
			a: Math.sin(i * 0.5) * 10.0,
			b: Math.sin(i * 0.5) * 1.0
		}];
		var h = new HasbrouckInformationShare(20);
		var last = lastNonNull(IndicatorBatch.run(h, pairs));
		Assert.isTrue(last > 0.8);
	}

	public function testHasbrouckEqualVenuesStayInBounds() {
		var pairs = [for (i in 0...200) {
			a: Math.sin(i * 0.5) * 5.0,
			b: Math.cos(i * 0.5) * 5.0
		}];
		var h = new HasbrouckInformationShare(40);
		var out = IndicatorBatch.run(h, pairs);
		for (v in out) if (v != null) Assert.isTrue(v >= 0.0 && v <= 1.0);
	}

	public function testHasbrouckFlatSeriesIsHalf() {
		var pairs = [for (_ in 0...20) {a: 7.0, b: 9.0}];
		var h = new HasbrouckInformationShare(5);
		var last = lastNonNull(IndicatorBatch.run(h, pairs));
		Assert.floatEquals(0.5, last);
	}

	public function testHasbrouckResetClearsState() {
		var h = new HasbrouckInformationShare(4);
		IndicatorBatch.run(h, [{a: 1.0, b: 1.0}, {a: 2.0, b: 2.0}, {a: 3.0, b: 3.0}, {a: 4.0, b: 4.0}, {a: 5.0, b: 5.0}]);
		Assert.isTrue(h.isReady());
		h.reset();
		Assert.isTrue(!h.isReady());
		Assert.isNull(h.update({a: 1.0, b: 1.0}));
	}

	public function testHasbrouckBatchEqualsStreaming() {
		var pairs = [for (i in 0...120) {
			a: Math.sin(i) * 5.0,
			b: Math.cos(i * 0.5) * 3.0
		}];
		var a = new HasbrouckInformationShare(20);
		var b = new HasbrouckInformationShare(20);
		assertSame(IndicatorBatch.run(a, pairs), [for (p in pairs) b.update(p)]);
	}

	public function testHasbrouckNonFiniteInputReturnsNone() {
		var h = new HasbrouckInformationShare(2);
		Assert.isNull(h.update({a: Math.NaN, b: 1.0}));
		Assert.isNull(h.update({a: 1.0, b: Math.POSITIVE_INFINITY}));
		// First finite tick seeds prev; two more returns fill the window.
		Assert.isNull(h.update({a: 1.0, b: 1.0}));
		Assert.isNull(h.update({a: 2.0, b: 3.0}));
		Assert.notNull(h.update({a: 3.0, b: 4.0}));
	}
}
