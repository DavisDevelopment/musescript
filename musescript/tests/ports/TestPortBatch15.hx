package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 15: 10 indicators (hurst_exponent, k_ratio, kelly_criterion, kama,
 * keltner, jarque_bera, jump_indicator, intraday_momentum_index,
 * kendall_tau, inertia) — standard published formulas (see PORTING.md note
 * on no local Wickra source clone).
 */
class TestPortBatch15 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── HurstExponent ─────────────────────────────────────────────────────

	public function testHurstExponentFlatSeriesIsNeutral() {
		var h = new HurstExponent(20);
		var out = null;
		for (i in 0...25) out = h.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.5, out, 1e-9);
	}

	public function testHurstExponentBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new HurstExponent(20), b = new HurstExponent(20);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── KRatio ────────────────────────────────────────────────────────────

	public function testKRatioPositiveOnSteadyGrowth() {
		var kr = new KRatio(20);
		var out = null;
		var equity = 100.0;
		for (i in 0...25) { equity *= 1.01; out = kr.update(equity); }
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── KellyCriterion ────────────────────────────────────────────────────

	public function testKellyCriterionPositiveWithGoodEdge() {
		var kc = new KellyCriterion(10);
		var pnls = [10.0, -5.0, 10.0, -5.0, 10.0, -5.0, 10.0, -5.0, 10.0, 10.0];
		var out = null;
		for (p in pnls) out = kc.update(p);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testKellyCriterionZeroWithNoLosses() {
		var kc = new KellyCriterion(5);
		var out = null;
		for (i in 0...5) out = kc.update(10.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── Kama ──────────────────────────────────────────────────────────────

	public function testKamaFlatSeriesConvergesToConstant() {
		var k = new Kama(10, 2, 30);
		var out = null;
		for (i in 0...20) out = k.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-9);
	}

	public function testKamaBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new Kama(10, 2, 30), b = new Kama(10, 2, 30);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Keltner ───────────────────────────────────────────────────────────

	public function testKeltnerUpperAboveMiddleAboveLower() {
		var k = new Keltner(20, 10, 2.0);
		for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var out = k.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
			if (out != null) {
				Assert.isTrue(out.upper >= out.middle);
				Assert.isTrue(out.middle >= out.lower);
			}
		}
	}

	// ── JarqueBera ────────────────────────────────────────────────────────

	public function testJarqueBeraZeroOnFlatSeries() {
		var jb = new JarqueBera(10);
		var out = null;
		for (i in 0...15) out = jb.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testJarqueBeraNonNegative() {
		var jb = new JarqueBera(20);
		for (i in 0...50) {
			var out = jb.update(100.0 + Math.sin(i * 0.5) * 5.0 + (i % 11 == 0 ? 10.0 : 0.0));
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	// ── JumpIndicator ─────────────────────────────────────────────────────

	public function testJumpIndicatorDetectsLargeOutlier() {
		var ji = new JumpIndicator(10, 3.0);
		var out = null;
		for (i in 0...12) out = ji.update(100.0 + (i % 2 == 0 ? 0.1 : -0.1));
		// small, steady oscillation shouldn't jump.
		Assert.notNull(out);
		Assert.floatEquals(0.0, out);
		// then a genuine outlier bar.
		out = ji.update(500.0);
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── IntradayMomentumIndex ─────────────────────────────────────────────

	public function testIntradayMomentumIndexAllGreenIsHundred() {
		var imi = new IntradayMomentumIndex(5);
		var out = null;
		for (i in 0...8) out = imi.update(bar(10.0, 12.0, 9.0, 11.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(100.0, out, 1e-9);
	}

	public function testIntradayMomentumIndexAllRedIsZero() {
		var imi = new IntradayMomentumIndex(5);
		var out = null;
		for (i in 0...8) out = imi.update(bar(11.0, 12.0, 9.0, 10.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── KendallTau ────────────────────────────────────────────────────────

	public function testKendallTauPerfectAgreementIsOne() {
		var kt = new KendallTau(10);
		var out = null;
		for (i in 0...12) out = kt.update({ a: i * 1.0, b: i * 2.0 });
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	public function testKendallTauPerfectDisagreementIsNegativeOne() {
		var kt = new KendallTau(10);
		var out = null;
		for (i in 0...12) out = kt.update({ a: i * 1.0, b: -i * 2.0 });
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out, 1e-9);
	}

	// ── Inertia ───────────────────────────────────────────────────────────

	public function testInertiaBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(base, base + 1.5, base - 1.5, base + (i % 3 == 0 ? 0.5 : -0.2), 1.0);
		}];
		var a = new Inertia(10, 14), b = new Inertia(10, 14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
