package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.RollingCorrelation;
import musescript.indicators.lib.RollingCovariance;
import musescript.indicators.lib.RollingIqr;
import musescript.indicators.lib.RollingMinMaxScaler;
import musescript.indicators.lib.RollingPercentileRank;
import musescript.indicators.lib.RollingQuantile;
import musescript.indicators.lib.SampleEntropy;
import musescript.indicators.lib.ShannonEntropy;
import musescript.indicators.lib.Skewness;
import musescript.indicators.lib.Variance;
import musescript.indicators.lib.StdDev;
import musescript.indicators.lib.ZScore;
import musescript.indicators.lib.StandardError;
import musescript.indicators.lib.StandardErrorBands;
import musescript.indicators.lib.SpearmanCorrelation;
import musescript.indicators.lib.SeasonalZScore;
import musescript.indicators.lib.VarianceRatio;
import musescript.indicators.lib.Rocr100;

/**
 * Batch 41: 18 rolling-statistics & entropy indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch41 extends Test {
	static function assertSameSeries(batched:Array<Null<Float>>, streamed:Array<Null<Float>>) {
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

	// ── RollingCorrelation ───────────────────────────────────────────────────

	public function testRollingCorrelationRejectsPeriodBelowTwo() {
		try {
			new RollingCorrelation(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new RollingCorrelation(1);
			Assert.fail("Should reject period 1");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new RollingCorrelation(2));
	}

	public function testRollingCorrelationAccessorsAndMetadata() {
		var rc = new RollingCorrelation(14);
		Assert.equals(15, rc.warmupPeriod());
		Assert.equals("RollingCorrelation", rc.name());
		Assert.isTrue(!rc.isReady());
	}

	public function testRollingCorrelationWarmupNeedsPeriodPlusOne() {
		var rc = new RollingCorrelation(3);
		// First update only seeds the previous level ⇒ null.
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
		Assert.isNull(rc.update({x: 2.0, y: 3.0})); // 1 return
		Assert.isNull(rc.update({x: 3.0, y: 5.0})); // 2 returns
		Assert.notNull(rc.update({x: 4.0, y: 7.0})); // 3 returns ⇒ ready
		Assert.isTrue(rc.isReady());
	}

	public function testRollingCorrelationComovingReturnsArePlusOne() {
		// y always moves by 2x x's move ⇒ perfectly correlated returns.
		var rc = new RollingCorrelation(8);
		var outs:Array<Null<Float>> = [];
		for (i in 0...20) {
			var x = Math.sin(i * 0.5) * 10.0;
			outs.push(rc.update({x: x, y: 2.0 * x + 100.0}));
		}
		Assert.floatEquals(1.0, lastNonNull(outs), 1e-9);
	}

	public function testRollingCorrelationOpposingReturnsAreMinusOne() {
		var rc = new RollingCorrelation(8);
		var outs:Array<Null<Float>> = [];
		for (i in 0...20) {
			var x = Math.sin(i * 0.5) * 10.0;
			outs.push(rc.update({x: x, y: -1.5 * x + 50.0}));
		}
		Assert.floatEquals(-1.0, lastNonNull(outs), 1e-9);
	}

	public function testRollingCorrelationFlatReturnChannelYieldsZero() {
		// y is constant ⇒ its returns are all zero ⇒ undefined ⇒ 0.
		var rc = new RollingCorrelation(6);
		var outs:Array<Null<Float>> = [];
		for (i in 0...20) outs.push(rc.update({x: i + 0.0, y: 7.0}));
		Assert.floatEquals(0.0, lastNonNull(outs), 1e-12);
	}

	public function testRollingCorrelationResetClearsState() {
		var rc = new RollingCorrelation(4);
		for (p in ([{x: 1.0, y: 2.0}, {x: 2.0, y: 4.0}, {x: 3.0, y: 6.0}, {x: 4.0, y: 8.0}, {x: 5.0, y: 10.0}] : Array<musescript.indicators.lib.RollingCorrelation.RollingCorrelationPair>))
			rc.update(p);
		Assert.isTrue(rc.isReady());
		rc.reset();
		Assert.isTrue(!rc.isReady());
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
	}

	public function testRollingCorrelationBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.RollingCorrelation.RollingCorrelationPair> = [for (i in 0...60) {x: Math.sin(i + 0.0), y: Math.cos(i * 0.5)}];
		var a = new RollingCorrelation(14);
		var b = new RollingCorrelation(14);
		assertSameSeries(IndicatorBatch.run(a, pairs), [for (p in pairs) b.update(p)]);
	}

	public function testRollingCorrelationNonFiniteInputReturnsNone() {
		var rc = new RollingCorrelation(2);
		Assert.isNull(rc.update({x: Math.NaN, y: 1.0}));
		Assert.isNull(rc.update({x: 1.0, y: Math.POSITIVE_INFINITY}));
		// First finite tick seeds prev; two more returns fill the window.
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
		Assert.isNull(rc.update({x: 2.0, y: 3.0}));
		Assert.notNull(rc.update({x: 3.0, y: 5.0}));
	}

	// ── RollingCovariance ────────────────────────────────────────────────────

	public function testRollingCovarianceRejectsPeriodBelowTwo() {
		try {
			new RollingCovariance(1);
			Assert.fail("Should reject period 1");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new RollingCovariance(2));
	}

	public function testRollingCovarianceAccessorsAndMetadata() {
		var rc = new RollingCovariance(14);
		Assert.equals(15, rc.warmupPeriod());
		Assert.equals("RollingCovariance", rc.name());
		Assert.isTrue(!rc.isReady());
	}

	public function testRollingCovarianceWarmupNeedsPeriodPlusOne() {
		var rc = new RollingCovariance(3);
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
		Assert.isNull(rc.update({x: 2.0, y: 3.0}));
		Assert.isNull(rc.update({x: 3.0, y: 5.0}));
		Assert.notNull(rc.update({x: 4.0, y: 7.0}));
		Assert.isTrue(rc.isReady());
	}

	public function testRollingCovarianceHandComputedValue() {
		// Levels x = 0,1,3,6,10 ⇒ returns 1,2,3,4; y = 2x ⇒ returns 2,4,6,8.
		// With period = 3 the final window is rx = [2,3,4], ry = [4,6,8]:
		//   Σrx·ry/3 = 58/3, r̄x·r̄y = 3·6 = 18 ⇒ cov = 58/3 − 18 = 4/3.
		var rc = new RollingCovariance(3);
		var outs:Array<Null<Float>> = [];
		for (p in ([{x: 0.0, y: 0.0}, {x: 1.0, y: 2.0}, {x: 3.0, y: 6.0}, {x: 6.0, y: 12.0}, {x: 10.0, y: 20.0}] : Array<musescript.indicators.lib.RollingCovariance.RollingCovariancePair>))
			outs.push(rc.update(p));
		Assert.floatEquals(4.0 / 3.0, lastNonNull(outs), 1e-9);
	}

	public function testRollingCovarianceOpposingReturnsGiveNegativeCovariance() {
		var rc = new RollingCovariance(10);
		var outs:Array<Null<Float>> = [];
		for (i in 0...30) {
			var x = Math.sin(i * 0.4) * 10.0;
			outs.push(rc.update({x: x, y: -x}));
		}
		Assert.isTrue(lastNonNull(outs) < 0.0);
	}

	public function testRollingCovarianceFlatChannelGivesZero() {
		var rc = new RollingCovariance(6);
		var outs:Array<Null<Float>> = [];
		for (i in 0...20) outs.push(rc.update({x: i + 0.0, y: 7.0}));
		Assert.floatEquals(0.0, lastNonNull(outs), 1e-12);
	}

	public function testRollingCovarianceResetClearsState() {
		var rc = new RollingCovariance(4);
		for (p in ([{x: 1.0, y: 2.0}, {x: 2.0, y: 4.0}, {x: 3.0, y: 1.0}, {x: 4.0, y: 9.0}, {x: 5.0, y: 2.0}] : Array<musescript.indicators.lib.RollingCovariance.RollingCovariancePair>))
			rc.update(p);
		Assert.isTrue(rc.isReady());
		rc.reset();
		Assert.isTrue(!rc.isReady());
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
	}

	public function testRollingCovarianceBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.RollingCovariance.RollingCovariancePair> = [for (i in 0...60) {x: Math.sin(i + 0.0) * 4.0, y: Math.cos(i * 0.5) * 2.0}];
		var a = new RollingCovariance(12);
		var b = new RollingCovariance(12);
		assertSameSeries(IndicatorBatch.run(a, pairs), [for (p in pairs) b.update(p)]);
	}

	public function testRollingCovarianceNonFiniteInputReturnsNone() {
		var rc = new RollingCovariance(2);
		Assert.isNull(rc.update({x: Math.NaN, y: 1.0}));
		Assert.isNull(rc.update({x: 1.0, y: Math.POSITIVE_INFINITY}));
		Assert.isNull(rc.update({x: 1.0, y: 1.0}));
		Assert.isNull(rc.update({x: 2.0, y: 3.0}));
		Assert.notNull(rc.update({x: 3.0, y: 5.0}));
	}

	// ── RollingIqr ───────────────────────────────────────────────────────────

	public function testRollingIqrRejectsZeroPeriod() {
		try {
			new RollingIqr(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRollingIqrAccessorsAndMetadata() {
		var iqr = new RollingIqr(14);
		Assert.equals(14, iqr.warmupPeriod());
		Assert.equals("RollingIqr", iqr.name());
		Assert.isTrue(!iqr.isReady());
	}

	public function testRollingIqrReferenceValue() {
		// sorted [10,20,30,40,50]: Q1 = 20, Q3 = 40. IQR = 40 - 20 = 20.
		var iqr = new RollingIqr(5);
		var out = IndicatorBatch.run(iqr, [50.0, 40.0, 30.0, 20.0, 10.0]);
		Assert.floatEquals(20.0, out[4], 1e-12);
	}

	public function testRollingIqrConstantSeriesYieldsZero() {
		var iqr = new RollingIqr(8);
		var outs = IndicatorBatch.run(iqr, [for (_ in 0...20) 42.0]);
		for (v in outs) if (v != null) Assert.floatEquals(0.0, v, 1e-12);
	}

	public function testRollingIqrIgnoresSingleExtremeOutlier() {
		// 19 tightly-clustered values plus one huge spike: the central 50%
		// is unaffected, so the IQR stays small (well below the spike scale).
		var iqr = new RollingIqr(20);
		var prices = [for (_ in 0...19) 5.0];
		prices.push(10000.0);
		var last = lastNonNull(IndicatorBatch.run(iqr, prices));
		Assert.isTrue(last < 1.0);
	}

	public function testRollingIqrResetClearsState() {
		var iqr = new RollingIqr(5);
		IndicatorBatch.run(iqr, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(iqr.isReady());
		iqr.reset();
		Assert.isTrue(!iqr.isReady());
		Assert.isNull(iqr.update(1.0));
	}

	public function testRollingIqrBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new RollingIqr(14);
		var b = new RollingIqr(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── RollingMinMaxScaler ──────────────────────────────────────────────────

	public function testRollingMinMaxScalerRejectsInvalidPeriod() {
		try {
			new RollingMinMaxScaler(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new RollingMinMaxScaler(1);
			Assert.fail("Should reject period 1");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new RollingMinMaxScaler(2));
	}

	public function testRollingMinMaxScalerAccessorsAndMetadata() {
		var s = new RollingMinMaxScaler(14);
		Assert.equals(14, s.warmupPeriod());
		Assert.equals("RollingMinMaxScaler", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testRollingMinMaxScalerFirstEmissionAtWarmupPeriod() {
		var s = new RollingMinMaxScaler(4);
		var out = IndicatorBatch.run(s, [1.0, 2.0, 3.0, 4.0, 5.0]);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testRollingMinMaxScalerHighestInWindowIsOne() {
		var s = new RollingMinMaxScaler(4);
		var last = lastNonNull(IndicatorBatch.run(s, [1.0, 2.0, 3.0, 4.0]));
		Assert.floatEquals(1.0, last, 1e-12);
	}

	public function testRollingMinMaxScalerLowestInWindowIsZero() {
		var s = new RollingMinMaxScaler(4);
		var last = lastNonNull(IndicatorBatch.run(s, [4.0, 3.0, 2.0, 1.0]));
		Assert.floatEquals(0.0, last, 1e-12);
	}

	public function testRollingMinMaxScalerMidpointIsHalf() {
		// window [0, 2, 1]: min 0, max 2, current 1 -> 0.5.
		var s = new RollingMinMaxScaler(3);
		var last = lastNonNull(IndicatorBatch.run(s, [0.0, 2.0, 1.0]));
		Assert.floatEquals(0.5, last, 1e-12);
	}

	public function testRollingMinMaxScalerFlatWindowIsHalf() {
		var s = new RollingMinMaxScaler(4);
		var last = lastNonNull(IndicatorBatch.run(s, [for (_ in 0...8) 7.0]));
		Assert.floatEquals(0.5, last, 1e-12);
	}

	public function testRollingMinMaxScalerIgnoresNonFinite() {
		var s = new RollingMinMaxScaler(4);
		var ready = lastNonNull(IndicatorBatch.run(s, [1.0, 2.0, 3.0, 4.0]));
		Assert.floatEquals(ready, s.update(Math.NaN));
	}

	public function testRollingMinMaxScalerResetClearsState() {
		var s = new RollingMinMaxScaler(4);
		IndicatorBatch.run(s, [1.0, 2.0, 3.0, 4.0]);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(1.0));
	}

	public function testRollingMinMaxScalerBatchEqualsStreaming() {
		var xs = [for (i in 0...120) Math.sin(i * 0.25) * 9.0];
		var a = new RollingMinMaxScaler(14);
		var b = new RollingMinMaxScaler(14);
		assertSameSeries(IndicatorBatch.run(a, xs), [for (x in xs) b.update(x)]);
	}

	// ── RollingPercentileRank ────────────────────────────────────────────────

	public function testRollingPercentileRankRejectsZeroPeriod() {
		try {
			new RollingPercentileRank(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRollingPercentileRankAccessorsAndMetadata() {
		var pr = new RollingPercentileRank(14);
		Assert.equals(14, pr.warmupPeriod());
		Assert.equals("RollingPercentileRank", pr.name());
		Assert.isTrue(!pr.isReady());
	}

	public function testRollingPercentileRankFlatWindowScoresFifty() {
		// All values equal: #below = 0, #equal = period → 0.5 → 50.
		var pr = new RollingPercentileRank(10);
		var outs = IndicatorBatch.run(pr, [for (_ in 0...20) 7.0]);
		for (v in outs) if (v != null) Assert.floatEquals(50.0, v, 1e-12);
	}

	public function testRollingPercentileRankCurrentIsStrictMaximum() {
		// Window [1,2,3,4,5], current = 5: (4 + 0.5) / 5 * 100 = 90.
		var pr = new RollingPercentileRank(5);
		var out = IndicatorBatch.run(pr, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.floatEquals(90.0, out[4], 1e-12);
	}

	public function testRollingPercentileRankCurrentIsStrictMinimum() {
		// Window [5,4,3,2,1], current = 1: (0 + 0.5) / 5 * 100 = 10.
		var pr = new RollingPercentileRank(5);
		var out = IndicatorBatch.run(pr, [5.0, 4.0, 3.0, 2.0, 1.0]);
		Assert.floatEquals(10.0, out[4], 1e-12);
	}

	public function testRollingPercentileRankResetClearsState() {
		var pr = new RollingPercentileRank(5);
		IndicatorBatch.run(pr, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(pr.isReady());
		pr.reset();
		Assert.isTrue(!pr.isReady());
		Assert.isNull(pr.update(1.0));
	}

	public function testRollingPercentileRankBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new RollingPercentileRank(14);
		var b = new RollingPercentileRank(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── RollingQuantile ──────────────────────────────────────────────────────

	public function testRollingQuantileRejectsZeroPeriod() {
		try {
			new RollingQuantile(0, 0.5);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRollingQuantileRejectsOutOfRangeQuantile() {
		try {
			new RollingQuantile(5, -0.1);
			Assert.fail("Should reject quantile < 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new RollingQuantile(5, 1.1);
			Assert.fail("Should reject quantile > 1");
		} catch (e:Dynamic) Assert.pass();
		try {
			new RollingQuantile(5, Math.NaN);
			Assert.fail("Should reject NaN quantile");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRollingQuantileAccessorsAndMetadata() {
		var q = new RollingQuantile(14, 0.25);
		Assert.equals(14, q.warmupPeriod());
		Assert.equals("RollingQuantile", q.name());
		Assert.isTrue(!q.isReady());
	}

	public function testRollingQuantileMedianOfWindow() {
		// Window [5, 1, 3, 2, 4] sorted [1,2,3,4,5] → median 3.
		var q = new RollingQuantile(5, 0.5);
		var out = IndicatorBatch.run(q, [5.0, 1.0, 3.0, 2.0, 4.0]);
		Assert.floatEquals(3.0, out[4], 1e-12);
	}

	public function testRollingQuantileMinAndMaxQuantiles() {
		var prices = [5.0, 1.0, 3.0, 2.0, 4.0];
		var lo = IndicatorBatch.run(new RollingQuantile(5, 0.0), prices)[4];
		var hi = IndicatorBatch.run(new RollingQuantile(5, 1.0), prices)[4];
		Assert.floatEquals(1.0, lo, 1e-12);
		Assert.floatEquals(5.0, hi, 1e-12);
	}

	public function testRollingQuantileInterpolatedQuantile() {
		// sorted [10,20,30,40]: q=0.25 → h=(4-1)*0.25=0.75 → 10 + 0.75*(20-10)=17.5.
		var q = new RollingQuantile(4, 0.25);
		var out = IndicatorBatch.run(q, [40.0, 30.0, 20.0, 10.0]);
		Assert.floatEquals(17.5, out[3], 1e-12);
	}

	public function testRollingQuantileSinglePeriodReturnsValue() {
		// period 1: window holds one value; quantile of a singleton is itself.
		var q = new RollingQuantile(1, 0.3);
		Assert.floatEquals(7.0, q.update(7.0), 1e-12);
	}

	public function testRollingQuantileResetClearsState() {
		var q = new RollingQuantile(5, 0.5);
		IndicatorBatch.run(q, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(q.isReady());
		q.reset();
		Assert.isTrue(!q.isReady());
		Assert.isNull(q.update(1.0));
	}

	public function testRollingQuantileBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new RollingQuantile(14, 0.75);
		var b = new RollingQuantile(14, 0.75);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── SampleEntropy ────────────────────────────────────────────────────────

	public function testSampleEntropyRejectsInvalidParams() {
		try {
			new SampleEntropy(0, 2, 0.2);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new SampleEntropy(50, 0, 0.2);
			Assert.fail("Should reject m 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new SampleEntropy(3, 2, 0.2);
			Assert.fail("Should reject period < m + 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new SampleEntropy(50, 2, 0.0);
			Assert.fail("Should reject r_factor 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testSampleEntropyAccessorsAndMetadata() {
		var s = new SampleEntropy(50, 2, 0.2);
		Assert.equals(50, s.warmupPeriod());
		Assert.equals("SampleEntropy", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testSampleEntropyFirstEmissionAtWarmupPeriod() {
		var s = new SampleEntropy(10, 2, 0.2);
		var xs = [for (i in 0...14) Math.sin(i * 0.5)];
		var out = IndicatorBatch.run(s, xs);
		for (i in 0...9) Assert.isNull(out[i]);
		Assert.notNull(out[9]);
	}

	public function testSampleEntropyConstantWindowIsZero() {
		var s = new SampleEntropy(20, 2, 0.2);
		var last = lastNonNull(IndicatorBatch.run(s, [for (_ in 0...30) 5.0]));
		Assert.floatEquals(0.0, last, 1e-12);
	}

	public function testSampleEntropyRegularBelowIrregular() {
		// A smooth sine is far more regular (lower SampEn) than a chaotic
		// logistic-map series.
		var smooth = [for (i in 0...60) Math.sin(i * 0.2) * 5.0];
		var x = 0.37;
		var chaotic = [for (_ in 0...60) {
			x = 3.99 * x * (1.0 - x);
			x * 5.0;
		}];
		var sSmooth = lastNonNull(IndicatorBatch.run(new SampleEntropy(50, 2, 0.2), smooth));
		var sChaotic = lastNonNull(IndicatorBatch.run(new SampleEntropy(50, 2, 0.2), chaotic));
		Assert.isTrue(sSmooth <= sChaotic, 'smooth (${sSmooth}) should be <= chaotic (${sChaotic})');
	}

	public function testSampleEntropyIgnoresNonFinite() {
		var s = new SampleEntropy(10, 2, 0.2);
		var xs = [for (i in 0...10) Math.sin(i * 0.5)];
		var ready = lastNonNull(IndicatorBatch.run(s, xs));
		Assert.floatEquals(ready, s.update(Math.NaN));
	}

	public function testSampleEntropyResetClearsState() {
		var s = new SampleEntropy(10, 2, 0.2);
		IndicatorBatch.run(s, [for (i in 0...10) Math.sin(i * 0.5)]);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(1.0));
	}

	public function testSampleEntropyBatchEqualsStreaming() {
		var xs = [for (i in 0...120) Math.sin(i * 0.25) * 9.0];
		var a = new SampleEntropy(40, 2, 0.2);
		var b = new SampleEntropy(40, 2, 0.2);
		assertSameSeries(IndicatorBatch.run(a, xs), [for (v in xs) b.update(v)]);
	}

	public function testSampleEntropyFallsBackWhenNoMPlusOneMatches() {
		// [1, 1, 1, 5] with m = 2: the length-2 template (1, 1) repeats
		// (matches_m > 0) but no length-3 template repeats (matches_m1 == 0),
		// so SampEn takes the ln(matches_m) fallback branch.
		var v = lastNonNull(IndicatorBatch.run(new SampleEntropy(4, 2, 0.2), [1.0, 1.0, 1.0, 5.0]));
		Assert.isTrue(Math.isFinite(v) && v >= 0.0);
	}

	// ── ShannonEntropy ───────────────────────────────────────────────────────

	public function testShannonEntropyRejectsInvalidParams() {
		try {
			new ShannonEntropy(0, 8);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new ShannonEntropy(32, 0);
			Assert.fail("Should reject bins 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new ShannonEntropy(32, 1);
			Assert.fail("Should reject bins 1");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testShannonEntropyAccessorsAndMetadata() {
		var e = new ShannonEntropy(32, 8);
		Assert.equals(32, e.warmupPeriod());
		Assert.equals("ShannonEntropy", e.name());
		Assert.isTrue(!e.isReady());
	}

	public function testShannonEntropyFirstEmissionAtWarmupPeriod() {
		var e = new ShannonEntropy(4, 4);
		var out = IndicatorBatch.run(e, [1.0, 2.0, 3.0, 4.0, 5.0]);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testShannonEntropyConstantWindowIsZero() {
		var e = new ShannonEntropy(8, 4);
		var last = lastNonNull(IndicatorBatch.run(e, [for (_ in 0...12) 5.0]));
		Assert.floatEquals(0.0, last, 1e-12);
	}

	public function testShannonEntropyUniformWindowIsMaxEntropy() {
		// One value per bin -> uniform distribution -> H = log2(4) = 2.
		var e = new ShannonEntropy(4, 4);
		var last = lastNonNull(IndicatorBatch.run(e, [0.0, 1.0, 2.0, 3.0]));
		Assert.floatEquals(2.0, last, 1e-9);
	}

	public function testShannonEntropyIgnoresNonFinite() {
		var e = new ShannonEntropy(4, 4);
		var ready = lastNonNull(IndicatorBatch.run(e, [1.0, 2.0, 3.0, 4.0]));
		Assert.floatEquals(ready, e.update(Math.NaN));
	}

	public function testShannonEntropyResetClearsState() {
		var e = new ShannonEntropy(4, 4);
		IndicatorBatch.run(e, [1.0, 2.0, 3.0, 4.0]);
		Assert.isTrue(e.isReady());
		e.reset();
		Assert.isTrue(!e.isReady());
		Assert.isNull(e.update(1.0));
	}

	public function testShannonEntropyBatchEqualsStreaming() {
		var xs = [for (i in 0...120) Math.sin(i * 0.25) * 9.0];
		var a = new ShannonEntropy(32, 8);
		var b = new ShannonEntropy(32, 8);
		assertSameSeries(IndicatorBatch.run(a, xs), [for (v in xs) b.update(v)]);
	}

	// ── Skewness ─────────────────────────────────────────────────────────────

	public function testSkewnessRejectsPeriodBelowThree() {
		for (p in [0, 1, 2]) {
			try {
				new Skewness(p);
				Assert.fail('Should reject period ${p}');
			} catch (e:Dynamic) Assert.pass();
		}
		Assert.notNull(new Skewness(3));
	}

	public function testSkewnessAccessorsAndMetadata() {
		var s = new Skewness(14);
		Assert.equals(14, s.warmupPeriod());
		Assert.equals("Skewness", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testSkewnessSymmetricWindowIsZero() {
		var s = new Skewness(5);
		var out = IndicatorBatch.run(s, [-2.0, -1.0, 0.0, 1.0, 2.0]);
		Assert.floatEquals(0.0, out[4], 1e-9);
	}

	public function testSkewnessConstantSeriesYieldsZero() {
		var s = new Skewness(5);
		var outs = IndicatorBatch.run(s, [for (_ in 0...20) 42.0]);
		for (v in outs) if (v != null) Assert.floatEquals(0.0, v, 1e-12);
	}

	public function testSkewnessRightTailIsPositive() {
		// One large positive outlier creates a right-skewed window.
		var s = new Skewness(5);
		var out = IndicatorBatch.run(s, [0.0, 0.0, 0.0, 0.0, 10.0]);
		Assert.isTrue(out[4] > 0.0);
	}

	public function testSkewnessLeftTailIsNegative() {
		var s = new Skewness(5);
		var out = IndicatorBatch.run(s, [10.0, 10.0, 10.0, 10.0, 0.0]);
		Assert.isTrue(out[4] < 0.0);
	}

	public function testSkewnessResetClearsState() {
		var s = new Skewness(5);
		IndicatorBatch.run(s, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(1.0));
	}

	public function testSkewnessBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 7.0];
		var a = new Skewness(14);
		var b = new Skewness(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Variance ─────────────────────────────────────────────────────────────

	public function testVarianceRejectsZeroPeriod() {
		try {
			new Variance(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testVarianceAccessorsAndMetadata() {
		var v = new Variance(14);
		Assert.equals(14, v.warmupPeriod());
		Assert.equals("Variance", v.name());
		Assert.isTrue(!v.isReady());
	}

	public function testVarianceReferenceValue() {
		// Variance(3) of [2, 4, 6]: mean = 4, variance = (4 + 0 + 4) / 3 = 8/3.
		var v = new Variance(3);
		var out = IndicatorBatch.run(v, [2.0, 4.0, 6.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(8.0 / 3.0, out[2], 1e-12);
	}

	public function testVarianceConstantSeriesYieldsZero() {
		var v = new Variance(5);
		var outs = IndicatorBatch.run(v, [for (_ in 0...20) 42.0]);
		for (o in outs) if (o != null) Assert.floatEquals(0.0, o, 1e-12);
	}

	public function testVarianceFirstValueOnPeriodThInput() {
		var v = new Variance(5);
		var out = IndicatorBatch.run(v, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testVarianceEqualsStdDevSquared() {
		// The rolling Variance must equal the rolling population StdDev squared.
		var prices = [for (i in 0...60) 50.0 + Math.sin(i * 0.3) * 7.0];
		var varInd = new Variance(14);
		var sd = new StdDev(14);
		for (p in prices) {
			var v = varInd.update(p);
			var s = sd.update(p);
			Assert.equals(v == null, s == null);
			if (v != null && s != null) Assert.floatEquals(v, s * s, 1e-9);
		}
	}

	public function testVarianceResetClearsState() {
		var v = new Variance(5);
		IndicatorBatch.run(v, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(1.0));
	}

	public function testVarianceBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 50.0 + Math.cos(i * 0.3) * 10.0];
		var a = new Variance(14);
		var b = new Variance(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── StdDev (population, lib) ─────────────────────────────────────────────

	public function testStdDevRejectsZeroPeriod() {
		try {
			new StdDev(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testStdDevAccessorsAndMetadata() {
		var sd = new StdDev(14);
		Assert.equals(14, sd.warmupPeriod());
		Assert.equals("StdDev", sd.name());
		Assert.isTrue(!sd.isReady());
		for (i in 1...15) sd.update(i + 0.0);
		Assert.isTrue(sd.isReady());
	}

	public function testStdDevReferenceValue() {
		// StdDev(3) of [2, 4, 6]: mean = 4, variance = (4+0+4)/3 = 8/3.
		var sd = new StdDev(3);
		var out = IndicatorBatch.run(sd, [2.0, 4.0, 6.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(Math.sqrt(8.0 / 3.0), out[2], 1e-12);
	}

	public function testStdDevConstantSeriesYieldsZero() {
		var sd = new StdDev(5);
		var out = IndicatorBatch.run(sd, [for (_ in 0...20) 42.0]);
		for (i in 4...out.length) if (out[i] != null) Assert.floatEquals(0.0, out[i], 1e-12);
	}

	public function testStdDevIgnoresNonFiniteInput() {
		var sd = new StdDev(3);
		var out = IndicatorBatch.run(sd, [2.0, 4.0, 6.0]);
		var last = out[2];
		Assert.notNull(last);
		Assert.floatEquals(last, sd.update(Math.NaN));
		Assert.floatEquals(last, sd.update(Math.POSITIVE_INFINITY));
	}

	public function testStdDevResetClearsState() {
		var sd = new StdDev(3);
		IndicatorBatch.run(sd, [1.0, 2.0, 3.0, 4.0]);
		Assert.isTrue(sd.isReady());
		sd.reset();
		Assert.isTrue(!sd.isReady());
		Assert.isNull(sd.update(1.0));
	}

	public function testStdDevBatchEqualsStreaming() {
		var prices = [for (i in 1...61) 100.0 + Math.cos(i * 0.3) * 7.0];
		var a = new StdDev(14);
		var b = new StdDev(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── ZScore ───────────────────────────────────────────────────────────────

	public function testZScoreReferenceValues() {
		// Window [1, 3]: mean 2, population variance (1 + 9)/2 − 4 = 1,
		// stddev 1; the latest price 3 is (3 − 2) / 1 = 1 stddev above.
		var z = new ZScore(2);
		var out = IndicatorBatch.run(z, [1.0, 3.0]);
		Assert.isNull(out[0]);
		Assert.floatEquals(1.0, out[1], 1e-12);
	}

	public function testZScoreConstantSeriesYieldsZero() {
		var z = new ZScore(10);
		var outs = IndicatorBatch.run(z, [for (_ in 0...30) 42.0]);
		for (v in outs) if (v != null) Assert.floatEquals(0.0, v, 1e-12);
	}

	public function testZScoreRisingPriceIsAboveItsMean() {
		var prices = [for (i in 0...40) i + 0.0];
		var z = new ZScore(10);
		var outs = IndicatorBatch.run(z, prices);
		for (v in outs) if (v != null) Assert.isTrue(v > 0.0);
	}

	public function testZScoreFirstValueOnPeriodThInput() {
		var z = new ZScore(5);
		var out = IndicatorBatch.run(z, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
		Assert.equals(5, z.warmupPeriod());
	}

	public function testZScoreRejectsZeroPeriod() {
		try {
			new ZScore(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testZScoreAccessorsAndMetadata() {
		var z = new ZScore(20);
		Assert.equals("ZScore", z.name());
		Assert.isTrue(!z.isReady());
	}

	public function testZScoreResetClearsState() {
		var z = new ZScore(5);
		IndicatorBatch.run(z, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(z.isReady());
		z.reset();
		Assert.isTrue(!z.isReady());
		Assert.isNull(z.update(1.0));
	}

	public function testZScoreBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 50.0 + Math.sin(i * 0.3) * 10.0];
		var a = new ZScore(20);
		var b = new ZScore(20);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── StandardError ────────────────────────────────────────────────────────

	public function testStandardErrorRejectsPeriodBelowThree() {
		try {
			new StandardError(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new StandardError(2);
			Assert.fail("Should reject period 2");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new StandardError(3));
	}

	public function testStandardErrorAccessorsAndMetadata() {
		var se = new StandardError(14);
		Assert.equals(14, se.warmupPeriod());
		Assert.equals("StandardError", se.name());
		Assert.isTrue(!se.isReady());
	}

	public function testStandardErrorPerfectLineHasZeroError() {
		// Residuals from a perfectly linear fit are zero, so SE = 0.
		var prices = [for (i in 0...30) 2.0 * i + 5.0];
		var se = new StandardError(10);
		var outs = IndicatorBatch.run(se, prices);
		for (v in outs) if (v != null) Assert.floatEquals(0.0, v, 1e-9);
	}

	public function testStandardErrorConstantSeriesYieldsZero() {
		var se = new StandardError(5);
		var outs = IndicatorBatch.run(se, [for (_ in 0...20) 42.0]);
		for (v in outs) if (v != null) Assert.floatEquals(0.0, v, 1e-9);
	}

	public function testStandardErrorMatchesNaiveDefinition() {
		// Compare the O(1) update against a fresh-from-scratch OLS refit each bar.
		function naive(window:Array<Float>):Float {
			var n:Float = window.length;
			var meanY = 0.0;
			for (y in window) meanY += y;
			meanY /= n;
			var sumXy = 0.0, sumX = 0.0, sumXx = 0.0;
			for (i in 0...window.length) {
				var x:Float = i;
				sumXy += x * window[i];
				sumX += x;
				sumXx += x * x;
			}
			var meanX = sumX / n;
			var sXx = sumXx - n * meanX * meanX;
			var slope = (sumXy - n * meanX * meanY) / sXx;
			var intercept = meanY - slope * meanX;
			var rss = 0.0;
			for (i in 0...window.length) {
				var r = window[i] - (intercept + slope * i);
				rss += r * r;
			}
			return Math.sqrt(rss / (n - 2.0));
		}

		var prices = [for (i in 0...60) 100.0 + i * 0.5 + Math.sin(i * 0.7) * 3.0];
		var period = 14;
		var got = IndicatorBatch.run(new StandardError(period), prices);
		for (i in 0...got.length) {
			if (got[i] != null) {
				var expected = naive(prices.slice(i + 1 - period, i + 1));
				Assert.floatEquals(expected, got[i], 1e-9);
			}
		}
	}

	public function testStandardErrorResetClearsState() {
		var se = new StandardError(5);
		IndicatorBatch.run(se, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(se.isReady());
		se.reset();
		Assert.isTrue(!se.isReady());
		Assert.isNull(se.update(1.0));
	}

	public function testStandardErrorBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.4) * 10.0];
		var a = new StandardError(14);
		var b = new StandardError(14);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── StandardErrorBands ───────────────────────────────────────────────────

	public function testStandardErrorBandsRejectsPeriodBelowThree() {
		for (p in [0, 1, 2]) {
			try {
				new StandardErrorBands(p, 2.0);
				Assert.fail('Should reject period ${p}');
			} catch (e:Dynamic) Assert.pass();
		}
		Assert.notNull(new StandardErrorBands(3, 2.0));
	}

	public function testStandardErrorBandsRejectsNonPositiveMultiplier() {
		for (m in [0.0, -1.0, Math.NaN]) {
			try {
				new StandardErrorBands(20, m);
				Assert.fail('Should reject multiplier ${m}');
			} catch (e:Dynamic) Assert.pass();
		}
	}

	public function testStandardErrorBandsAccessorsAndMetadata() {
		var seb = new StandardErrorBands(21, 2.0);
		Assert.equals(21, seb.warmupPeriod());
		Assert.equals("StandardErrorBands", seb.name());
		Assert.isTrue(!seb.isReady());
	}

	public function testStandardErrorBandsPerfectLineCollapsesBands() {
		var prices = [for (i in 0...40) 2.0 * i + 5.0];
		var seb = new StandardErrorBands(10, 2.0);
		for (o in IndicatorBatch.run(seb, prices)) {
			if (o != null) {
				Assert.floatEquals(o.middle, o.upper, 1e-9);
				Assert.floatEquals(o.lower, o.middle, 1e-9);
			}
		}
	}

	public function testStandardErrorBandsUpperAboveMiddleAboveLower() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.3) * 10.0];
		var seb = new StandardErrorBands(21, 2.0);
		for (o in IndicatorBatch.run(seb, prices)) {
			if (o != null) {
				Assert.isTrue(o.upper >= o.middle);
				Assert.isTrue(o.middle >= o.lower);
			}
		}
	}

	public function testStandardErrorBandsReferenceValues() {
		// period 3 over [1, 2, 9]. Fitted line y = 0 + 4·x, endpoint at x = 2
		// is 8. Residuals: 1, −2, 1. SSE = 6. n − 2 = 1 so stderr = sqrt(6).
		// With multiplier 2.0: upper = 8 + 2·sqrt(6), lower = 8 − 2·sqrt(6).
		var seb = new StandardErrorBands(3, 2.0);
		var v = IndicatorBatch.run(seb, [1.0, 2.0, 9.0])[2];
		var s = Math.sqrt(6.0);
		Assert.floatEquals(8.0, v.middle, 1e-9);
		Assert.floatEquals(8.0 + 2.0 * s, v.upper, 1e-9);
		Assert.floatEquals(8.0 - 2.0 * s, v.lower, 1e-9);
	}

	public function testStandardErrorBandsResetClearsState() {
		var seb = new StandardErrorBands(5, 2.0);
		IndicatorBatch.run(seb, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(seb.isReady());
		seb.reset();
		Assert.isTrue(!seb.isReady());
		Assert.isNull(seb.update(1.0));
	}

	public function testStandardErrorBandsBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 50.0 + Math.sin(i * 0.3) * 10.0];
		var a = new StandardErrorBands(21, 2.0);
		var b = new StandardErrorBands(21, 2.0);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].upper, streamed[i].upper);
				Assert.floatEquals(batched[i].middle, streamed[i].middle);
				Assert.floatEquals(batched[i].lower, streamed[i].lower);
			}
		}
	}

	// ── SpearmanCorrelation ──────────────────────────────────────────────────

	public function testSpearmanCorrelationRejectsPeriodBelowTwo() {
		try {
			new SpearmanCorrelation(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new SpearmanCorrelation(1);
			Assert.fail("Should reject period 1");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new SpearmanCorrelation(2));
	}

	public function testSpearmanCorrelationAccessorsAndMetadata() {
		var s = new SpearmanCorrelation(14);
		Assert.equals(14, s.warmupPeriod());
		Assert.equals("SpearmanCorrelation", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testSpearmanCorrelationPerfectMonotoneRelationshipIsOne() {
		// y = x³ is strictly monotone but very non-linear; Pearson would
		// not return exactly 1 but Spearman must.
		var s = new SpearmanCorrelation(5);
		var outs:Array<Null<Float>> = [];
		for (i in 1...11) outs.push(s.update({x: i + 0.0, y: Math.pow(i, 3)}));
		Assert.floatEquals(1.0, lastNonNull(outs), 1e-9);
	}

	public function testSpearmanCorrelationPerfectInverseIsMinusOne() {
		var s = new SpearmanCorrelation(5);
		var outs:Array<Null<Float>> = [];
		for (i in 1...11) outs.push(s.update({x: i + 0.0, y: 1.0 / i}));
		Assert.floatEquals(-1.0, lastNonNull(outs), 1e-9);
	}

	public function testSpearmanCorrelationConstantChannelYieldsZero() {
		var s = new SpearmanCorrelation(5);
		var outs:Array<Null<Float>> = [];
		for (i in 0...10) outs.push(s.update({x: i + 0.0, y: 7.0}));
		Assert.floatEquals(0.0, lastNonNull(outs), 1e-12);
	}

	public function testSpearmanCorrelationHandlesTiesViaMidRanks() {
		// Ranks: rx = [1, 2, 3.5, 3.5]; ry = [1, 2, 3, 4]. Pearson of those
		// is a positive number less than 1 because of the tie in rx.
		var s = new SpearmanCorrelation(4);
		var outs:Array<Null<Float>> = [];
		for (p in ([{x: 1.0, y: 1.0}, {x: 2.0, y: 2.0}, {x: 3.0, y: 3.0}, {x: 3.0, y: 4.0}] : Array<musescript.indicators.lib.SpearmanCorrelation.SpearmanPair>))
			outs.push(s.update(p));
		var last = lastNonNull(outs);
		Assert.isTrue(last > 0.0 && last < 1.0);
	}

	public function testSpearmanCorrelationResetClearsState() {
		var s = new SpearmanCorrelation(5);
		for (p in ([{x: 1.0, y: 2.0}, {x: 2.0, y: 4.0}, {x: 3.0, y: 6.0}, {x: 4.0, y: 8.0}, {x: 5.0, y: 10.0}] : Array<musescript.indicators.lib.SpearmanCorrelation.SpearmanPair>))
			s.update(p);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update({x: 1.0, y: 1.0}));
	}

	public function testSpearmanCorrelationBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.SpearmanCorrelation.SpearmanPair> = [for (i in 0...60) {x: Math.sin(i + 0.0) + Math.cos(i * 0.1), y: Math.cos(i * 0.3)}];
		var a = new SpearmanCorrelation(14);
		var b = new SpearmanCorrelation(14);
		assertSameSeries(IndicatorBatch.run(a, pairs), [for (p in pairs) b.update(p)]);
	}

	public function testSpearmanCorrelationNonFiniteInputReturnsNone() {
		var s = new SpearmanCorrelation(2);
		Assert.isNull(s.update({x: Math.NaN, y: 1.0}));
		Assert.isNull(s.update({x: 1.0, y: Math.POSITIVE_INFINITY}));
		// The rejected ticks leave no trace: a fresh window still warms up.
		Assert.isNull(s.update({x: 1.0, y: 2.0}));
		Assert.notNull(s.update({x: 2.0, y: 5.0}));
	}

	// ── SeasonalZScore ───────────────────────────────────────────────────────

	static inline var DAY_SECS = 24 * 3600;

	static function seasonBar(close:Float, timeSecs:Float, i:Int):Bar {
		return { open: close, high: close, low: close, close: close, volume: 1.0, time: timeSecs, index: i };
	}

	public function testSeasonalZScoreMetadataAndAccessors() {
		var z = new SeasonalZScore(120);
		Assert.equals("SeasonalZScore", z.name());
		Assert.equals(2, z.warmupPeriod());
		Assert.isTrue(!z.isReady());
	}

	public function testSeasonalZScoreNoOutputUntilBucketHasTwoPriors() {
		var z = new SeasonalZScore(0);
		// Each bar shares the same hour bucket (same time-of-day, daily spacing).
		Assert.isNull(z.update(seasonBar(100.0, 0, 0))); // first: no return
		Assert.isNull(z.update(seasonBar(101.0, DAY_SECS, 1))); // return #1 -> 0 priors
		Assert.isNull(z.update(seasonBar(102.0, 2 * DAY_SECS, 2))); // return #2 -> 1 prior
		// return #3 -> bucket has 2 priors -> emits.
		Assert.notNull(z.update(seasonBar(104.0, 3 * DAY_SECS, 3)));
		Assert.isTrue(z.isReady());
	}

	public function testSeasonalZScoreMatchesManualWelford() {
		var z = new SeasonalZScore(0);
		// Returns into one hourly bucket: r1 = 0.01, r2 = 0.02, r3 = 0.03.
		z.update(seasonBar(100.0, 0, 0));
		z.update(seasonBar(101.0, DAY_SECS, 1)); // r1 = 0.01
		z.update(seasonBar(103.02, 2 * DAY_SECS, 2)); // r2 = 0.02
		// Priors {0.01, 0.02}: mean 0.015, sample std = sqrt(((.005)^2*2)/1).
		var mean = 0.015;
		var std = Math.sqrt((Math.pow(0.01 - mean, 2) + Math.pow(0.02 - mean, 2)) / 1.0);
		var r3 = 0.03;
		var expected = (r3 - mean) / std;
		var close = 103.02 * (1.0 + r3);
		var out = z.update(seasonBar(close, 3 * DAY_SECS, 3));
		Assert.floatEquals(expected, out, 1e-9);
	}

	public function testSeasonalZScoreZeroVarianceBucketReportsZero() {
		var z = new SeasonalZScore(0);
		// Constant return into the bucket -> variance 0 -> z = 0.
		z.update(seasonBar(100.0, 0, 0));
		z.update(seasonBar(110.0, DAY_SECS, 1)); // r1 = 0.10
		z.update(seasonBar(121.0, 2 * DAY_SECS, 2)); // r2 = 0.10
		var out = z.update(seasonBar(133.1, 3 * DAY_SECS, 3)); // r3 = 0.10
		Assert.floatEquals(0.0, out);
	}

	public function testSeasonalZScoreZeroPrevCloseUsesZeroReturn() {
		var z = new SeasonalZScore(0);
		z.update(seasonBar(0.0, 0, 0)); // prev close 0
		z.update(seasonBar(0.0, DAY_SECS, 1)); // ret = 0 (guarded), bucket sample
		z.update(seasonBar(0.0, 2 * DAY_SECS, 2)); // ret = 0, bucket now 2 priors
		var out = z.update(seasonBar(0.0, 3 * DAY_SECS, 3));
		Assert.floatEquals(0.0, out);
	}

	public function testSeasonalZScoreResetClearsState() {
		var z = new SeasonalZScore(0);
		for (i in 0...4) z.update(seasonBar(100.0 + i, i * DAY_SECS, i));
		z.reset();
		Assert.isTrue(!z.isReady());
		Assert.isNull(z.update(seasonBar(100.0, 4 * DAY_SECS, 4)));
	}

	public function testSeasonalZScoreBatchEqualsStreaming() {
		var bars = [for (i in 0...50) seasonBar(100.0 + (i % 9), i * 3 * 3600, i)];
		var a = new SeasonalZScore(0);
		var b = new SeasonalZScore(0);
		assertSameSeries(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── VarianceRatio ────────────────────────────────────────────────────────

	public function testVarianceRatioRejectsBadParameters() {
		try {
			new VarianceRatio(10, 1);
			Assert.fail("Should reject q < 2");
		} catch (e:Dynamic) Assert.pass();
		try {
			new VarianceRatio(3, 2);
			Assert.fail("Should reject period < q + 2");
		} catch (e:Dynamic) Assert.pass();
		Assert.notNull(new VarianceRatio(4, 2));
	}

	public function testVarianceRatioAccessorsAndMetadata() {
		var vr = new VarianceRatio(60, 4);
		Assert.equals(60, vr.warmupPeriod());
		Assert.equals("VarianceRatio", vr.name());
		Assert.isTrue(!vr.isReady());
	}

	public function testVarianceRatioWarmupReturnsNone() {
		var vr = new VarianceRatio(4, 2);
		Assert.isNull(vr.update({a: 1.0, b: 0.0}));
		Assert.isNull(vr.update({a: 2.0, b: 0.0}));
		Assert.isNull(vr.update({a: 3.0, b: 0.0}));
		Assert.notNull(vr.update({a: 4.0, b: 0.0}));
		Assert.isTrue(vr.isReady());
	}

	public function testVarianceRatioAlternatingChangesGiveZeroRatio() {
		// Spreads 0,2,1,3,2 ⇒ changes 2,-1,2,-1; q = 2 overlapping sums are all
		// 1 (constant) ⇒ Var(q) = 0 ⇒ VR = 0 (perfect mean reversion).
		var vr = new VarianceRatio(5, 2);
		var outs:Array<Null<Float>> = [];
		for (p in ([{a: 0.0, b: 0.0}, {a: 2.0, b: 0.0}, {a: 1.0, b: 0.0}, {a: 3.0, b: 0.0}, {a: 2.0, b: 0.0}] : Array<musescript.indicators.lib.VarianceRatio.VarianceRatioPair>))
			outs.push(vr.update(p));
		Assert.floatEquals(0.0, lastNonNull(outs), 1e-12);
	}

	public function testVarianceRatioOscillatingSpreadIsBelowOne() {
		var vr = new VarianceRatio(60, 2);
		var outs:Array<Null<Float>> = [];
		for (t in 0...200) {
			var b = 100.0 + t;
			outs.push(vr.update({a: b + 2.0 * Math.sin(t * 2.5), b: b}));
		}
		Assert.isTrue(lastNonNull(outs) < 1.0);
	}

	public function testVarianceRatioFlatSpreadReturnsOne() {
		var vr = new VarianceRatio(10, 3);
		var outs:Array<Null<Float>> = [];
		for (t in 0...30) outs.push(vr.update({a: 5.0 + t, b: t + 0.0}));
		Assert.floatEquals(1.0, lastNonNull(outs));
	}

	public function testVarianceRatioOutputNonNegative() {
		var vr = new VarianceRatio(40, 4);
		for (t in 0...150) {
			var b = 50.0 + 0.3 * t;
			var v = vr.update({a: b + Math.sin(t * 0.5) * 2.0, b: b});
			if (v != null) Assert.isTrue(v >= 0.0);
		}
	}

	public function testVarianceRatioResetClearsState() {
		var vr = new VarianceRatio(6, 2);
		for (t in 0...12) vr.update({a: t + Math.sin(t * 0.7), b: t + 0.0});
		Assert.isTrue(vr.isReady());
		vr.reset();
		Assert.isTrue(!vr.isReady());
		Assert.isNull(vr.update({a: 1.0, b: 0.0}));
	}

	public function testVarianceRatioBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.VarianceRatio.VarianceRatioPair> = [for (t in 0...100) {
			var base = 30.0 + 0.7 * t;
			var p:musescript.indicators.lib.VarianceRatio.VarianceRatioPair = {a: base + Math.sin(t * 0.4) * 1.5, b: base};
			p;
		}];
		var a = new VarianceRatio(32, 3);
		var b = new VarianceRatio(32, 3);
		assertSameSeries(IndicatorBatch.run(a, pairs), [for (p in pairs) b.update(p)]);
	}

	public function testVarianceRatioNonFiniteInputReturnsNone() {
		var vr = new VarianceRatio(4, 2);
		Assert.isNull(vr.update({a: Math.NaN, b: 1.0}));
		Assert.isNull(vr.update({a: 1.0, b: Math.POSITIVE_INFINITY}));
		// The rejected ticks leave no trace: a fresh window still warms up.
		Assert.isNull(vr.update({a: 1.0, b: 0.0}));
		Assert.isNull(vr.update({a: 2.0, b: 0.0}));
		Assert.isNull(vr.update({a: 3.0, b: 0.0}));
		Assert.notNull(vr.update({a: 4.0, b: 0.0}));
	}

	// ── Rocr100 ──────────────────────────────────────────────────────────────

	public function testRocr100RejectsZeroPeriod() {
		try {
			new Rocr100(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRocr100AccessorsReportConfig() {
		var r = new Rocr100(3);
		Assert.equals("ROCR100", r.name());
		Assert.equals(4, r.warmupPeriod());
		Assert.isTrue(!r.isReady());
	}

	public function testRocr100KnownValueIsAScaledRatio() {
		// period 1 over [10, 11]: 11 / 10 * 100 = 110.
		var r = new Rocr100(1);
		var out = IndicatorBatch.run(r, [10.0, 11.0]);
		Assert.isNull(out[0]);
		Assert.floatEquals(110.0, out[1], 1e-12);
		Assert.isTrue(r.isReady());
	}

	public function testRocr100ConstantSeriesYieldsHundred() {
		var r = new Rocr100(3);
		var out = IndicatorBatch.run(r, [for (_ in 0...12) 10.0]);
		for (i in 4...out.length) if (out[i] != null) Assert.floatEquals(100.0, out[i], 1e-12);
	}

	public function testRocr100ZeroReferencePriceReportsZero() {
		var r = new Rocr100(1);
		var out = IndicatorBatch.run(r, [0.0, 5.0]);
		Assert.floatEquals(0.0, out[1], 1e-12);
	}

	public function testRocr100NonFiniteInputHoldsLast() {
		var r = new Rocr100(1);
		Assert.isNull(r.update(10.0));
		var v = r.update(11.0);
		Assert.notNull(v);
		Assert.floatEquals(v, r.update(Math.NEGATIVE_INFINITY));
	}

	public function testRocr100ResetClearsState() {
		var r = new Rocr100(1);
		IndicatorBatch.run(r, [10.0, 11.0]);
		Assert.isTrue(r.isReady());
		r.reset();
		Assert.isTrue(!r.isReady());
		Assert.isNull(r.update(10.0));
	}

	public function testRocr100BatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = new Rocr100(3);
		var b = new Rocr100(3);
		assertSameSeries(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}
}
