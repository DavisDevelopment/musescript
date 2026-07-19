package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.PearsonCorrelation;
import musescript.indicators.lib.PairSpreadZScore;
import musescript.indicators.lib.PairwiseBeta;
import musescript.indicators.lib.RelativeStrengthAB;
import musescript.indicators.lib.Cointegration;

/**
 * Batch 26: 5 Tier-1 pair-input indicators ported from wickra-core
 * (pearson_correlation, pair_spread_zscore, pairwise_beta, relative_strength_ab,
 * cointegration). Known-value cases transcribed from the Rust fixture blocks
 * in vendor/wickra/crates/wickra-core/src/indicators/<name>.rs. Cointegration's
 * heavier ADF-regression internals are exercised only via its public
 * accessors/rejection/batch_equals_streaming surface, not the private
 * adf_no_constant helper (not exposed by the port).
 */
class TestPortBatch26 extends Test {
	// ── PearsonCorrelation ───────────────────────────────────────────────

	public function testPearsonRejectsPeriodBelowTwo() {
		var exc = false;
		try new PearsonCorrelation(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PearsonCorrelation(1) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new PearsonCorrelation(2); // should not throw
	}

	public function testPearsonAccessorsAndMetadata() {
		var p = new PearsonCorrelation(14);
		Assert.equals(14, p.warmupPeriod());
		Assert.equals("PearsonCorrelation", p.name());
	}

	public function testPearsonPerfectPositiveIsOne() {
		var p = new PearsonCorrelation(5);
		var last:Null<Float> = null;
		for (i in 0...10) {
			var v = p.update({ x: i * 1.0, y: 3.0 * i + 1.0 });
			if (v != null) last = v;
		}
		Assert.notNull(last);
		Assert.floatEquals(1.0, last, 1e-9);
	}

	public function testPearsonBatchEqualsStreaming() {
		var xs = [for (i in 0...60) i * 1.0];
		var ys = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new PearsonCorrelation(10), b = new PearsonCorrelation(10);
		var batched = [for (i in 0...xs.length) a.update({ x: xs[i], y: ys[i] })];
		var streamed = [for (i in 0...xs.length) b.update({ x: xs[i], y: ys[i] })];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── PairSpreadZScore ─────────────────────────────────────────────────

	public function testPairSpreadRejectsPeriodsBelowTwo() {
		var exc = false;
		try new PairSpreadZScore(1, 5) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PairSpreadZScore(5, 1) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new PairSpreadZScore(2, 2); // should not throw
	}

	public function testPairSpreadAccessorsAndMetadata() {
		var z = new PairSpreadZScore(10, 20);
		Assert.equals(29, z.warmupPeriod());
		Assert.equals("PairSpreadZScore", z.name());
	}

	public function testPairSpreadFlatBenchmarkTwoSampleWindowIsSignOfMove() {
		var z = new PairSpreadZScore(2, 2);
		Assert.isNull(z.update({ a: 100.0, b: 100.0 }));
		Assert.isNull(z.update({ a: 100.0, b: 100.0 }));
		Assert.floatEquals(1.0, z.update({ a: 110.0, b: 100.0 }), 1e-9);
		Assert.floatEquals(-1.0, z.update({ a: 105.0, b: 100.0 }), 1e-9);
		Assert.floatEquals(1.0, z.update({ a: 130.0, b: 100.0 }), 1e-9);
	}

	public function testPairSpreadBatchEqualsStreaming() {
		var as_ = [for (i in 0...60) 100.0 + Math.sin(i * 0.25) * 6.0];
		var bs = [for (i in 0...60) 100.0 + Math.cos(i * 0.2) * 4.0];
		var x = new PairSpreadZScore(5, 10), y = new PairSpreadZScore(5, 10);
		var batched = [for (i in 0...as_.length) x.update({ a: as_[i], b: bs[i] })];
		var streamed = [for (i in 0...as_.length) y.update({ a: as_[i], b: bs[i] })];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── PairwiseBeta ─────────────────────────────────────────────────────

	public function testPairwiseBetaRejectsPeriodBelowTwo() {
		var exc = false;
		try new PairwiseBeta(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new PairwiseBeta(1) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new PairwiseBeta(2); // should not throw
	}

	public function testPairwiseBetaAccessorsAndMetadata() {
		var b = new PairwiseBeta(14);
		Assert.equals(15, b.warmupPeriod());
		Assert.equals("PairwiseBeta", b.name());
	}

	public function testPairwiseBetaSquaredPriceGivesBetaTwo() {
		var beta = new PairwiseBeta(5);
		var last:Null<Float> = null;
		for (i in 0...20) {
			var bv = 100.0 + 10.0 * Math.sin(i * 0.5);
			var v = beta.update({ a: bv * bv, b: bv });
			if (v != null) last = v;
		}
		Assert.notNull(last);
		Assert.floatEquals(2.0, last, 1e-6);
	}

	public function testPairwiseBetaBatchEqualsStreaming() {
		var as_ = [for (i in 0...60) 100.0 + Math.sin(i * 0.25) * 6.0];
		var bs = [for (i in 0...60) 100.0 + Math.cos(i * 0.2) * 4.0];
		var x = new PairwiseBeta(10), y = new PairwiseBeta(10);
		var batched = [for (i in 0...as_.length) x.update({ a: as_[i], b: bs[i] })];
		var streamed = [for (i in 0...as_.length) y.update({ a: as_[i], b: bs[i] })];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── RelativeStrengthAB ───────────────────────────────────────────────

	public function testRelativeStrengthRejectsZeroPeriods() {
		var exc = false;
		try new RelativeStrengthAB(0, 5) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new RelativeStrengthAB(5, 0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new RelativeStrengthAB(5, 5); // should not throw
	}

	public function testRelativeStrengthAccessorsAndMetadata() {
		var rs = new RelativeStrengthAB(10, 14);
		Assert.equals(15, rs.warmupPeriod());
		Assert.equals("RelativeStrengthAB", rs.name());
	}

	public function testRelativeStrengthConstantRatioIsFlat() {
		var rs = new RelativeStrengthAB(5, 5);
		var last = null;
		for (i in 0...20) {
			var v = rs.update({ a: 200.0, b: 100.0 });
			if (v != null) last = v;
		}
		Assert.notNull(last);
		Assert.floatEquals(2.0, last.ratio, 1e-9);
	}

	public function testRelativeStrengthBatchEqualsStreaming() {
		var as_ = [for (i in 0...60) 100.0 + Math.sin(i * 0.25) * 6.0];
		var bs = [for (i in 0...60) 100.0 + Math.cos(i * 0.2) * 4.0];
		var x = new RelativeStrengthAB(5, 5), y = new RelativeStrengthAB(5, 5);
		var batched = [for (i in 0...as_.length) x.update({ a: as_[i], b: bs[i] })];
		var streamed = [for (i in 0...as_.length) y.update({ a: as_[i], b: bs[i] })];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i].ratio, streamed[i].ratio, 1e-9);
		}
	}

	// ── Cointegration ────────────────────────────────────────────────────

	public function testCointegrationRejectsTooSmallPeriod() {
		var exc = false;
		try new Cointegration(3, 0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new Cointegration(4, 0); // should not throw
		exc = false;
		try new Cointegration(5, 1) catch (e:String) exc = true;
		Assert.isTrue(exc);
		new Cointegration(6, 1); // should not throw
	}

	public function testCointegrationAccessorsAndMetadata() {
		var c = new Cointegration(30, 2);
		Assert.equals(30, c.warmupPeriod());
		Assert.equals("Cointegration", c.name());
	}

	public function testCointegrationBatchEqualsStreaming() {
		var as_ = [for (i in 0...60) 100.0 + Math.sin(i * 0.25) * 6.0];
		var bs = [for (i in 0...60) 100.0 + Math.cos(i * 0.2) * 4.0];
		var x = new Cointegration(10, 1), y = new Cointegration(10, 1);
		var batched = [for (i in 0...as_.length) x.update({ a: as_[i], b: bs[i] })];
		var streamed = [for (i in 0...as_.length) y.update({ a: as_[i], b: bs[i] })];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i].hedge_ratio, streamed[i].hedge_ratio, 1e-9);
		}
	}
}
