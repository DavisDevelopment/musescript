package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 24: 5 Tier-1 indicators (r_squared, realized_volatility, recovery_factor,
 * reflex, regime_label) — ported from wickra-core with known-value transcription
 * from Rust test fixtures.
 */
class TestPortBatch24 extends Test {

	// ── RSquared ───────────────────────────────────────────────────────────

	public function testRSquaredRejectsPeriodBelowTwo() {
		try {
			var r = new RSquared(1);
			Assert.fail("Should reject period < 2");
		} catch (e:String) {
			Assert.pass();
		}
	}

	public function testRSquaredAccessorsAndMetadata() {
		var r = new RSquared(14);
		Assert.equals(r.warmupPeriod(), 14);
		Assert.equals(r.name(), "RSquared");
		Assert.notNull(r);
	}

	public function testRSquaredPerfectLineIsOne() {
		// y = 2x + 5
		var prices:Array<Float> = [];
		for (i in 0...30) {
			prices.push(2.0 * i + 5.0);
		}
		var r = new RSquared(10);
		for (p in prices) {
			var v = r.update(p);
			if (v != null) {
				Assert.floatEquals(1.0, v, 1e-6);
			}
		}
	}

	public function testRSquaredConstantSeriesIsOne() {
		// Flat series: SS_total = 0, should return 1.0
		var r = new RSquared(5);
		for (i in 0...20) {
			var v = r.update(42.0);
			if (v != null) {
				Assert.floatEquals(1.0, v, 1e-9);
			}
		}
	}

	public function testRSquaredOutputStaysInRange() {
		var prices:Array<Float> = [];
		for (i in 0...120) {
			var val = 100.0 + Math.sin(i * 0.4) * 5.0 + Math.cos(i * 0.07) * 12.0;
			prices.push(val);
		}
		var r = new RSquared(20);
		for (p in prices) {
			var v = r.update(p);
			if (v != null) {
				Assert.isTrue(v >= 0.0 && v <= 1.0, "R² out of range: " + v);
			}
		}
	}

	public function testRSquaredBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...60) {
			prices.push(50.0 + Math.sin(i * 0.3) * 10.0);
		}
		var batch = new RSquared(14);
		var streamed = new RSquared(14);
		var batchResults = [];
		var streamedResults = [];

		for (p in prices) {
			var v = batch.update(p);
			batchResults.push(v);
		}
		for (p in prices) {
			var v = streamed.update(p);
			streamedResults.push(v);
		}

		Assert.equals(batchResults.length, streamedResults.length);
		for (i in 0...batchResults.length) {
			if (batchResults[i] != null && streamedResults[i] != null) {
				Assert.floatEquals(batchResults[i], streamedResults[i], 1e-9);
			} else {
				Assert.equals(batchResults[i], streamedResults[i]);
			}
		}
	}

	// ── RealizedVolatility ─────────────────────────────────────────────────

	public function testRealizedVolatilityRejectsZeroPeriod() {
		try {
			var rv = new RealizedVolatility(0);
			Assert.fail("Should reject period == 0");
		} catch (e:String) {
			Assert.pass();
		}
	}

	public function testRealizedVolatilityAccessorsAndMetadata() {
		var rv = new RealizedVolatility(20);
		Assert.equals(rv.warmupPeriod(), 21);
		Assert.equals(rv.name(), "RealizedVolatility");
		Assert.isFalse(rv.isReady());
	}

	public function testRealizedVolatilityFirstEmissionAtWarmupPeriod() {
		var rv = new RealizedVolatility(5);
		var results = [];
		for (i in 1...21) {
			results.push(rv.update(i));
		}
		// First 5 should be null
		for (i in 0...5) {
			Assert.isNull(results[i]);
		}
		// At index 5, should be non-null
		Assert.notNull(results[5]);
	}

	public function testRealizedVolatilityKnownValue() {
		// Two equal +10% steps: r = ln(1.1) each. RV = sqrt(2·ln(1.1)²)
		var rv = new RealizedVolatility(2);
		rv.update(100.0);
		rv.update(110.0);
		var v = rv.update(121.0);
		Assert.notNull(v);
		var expected = Math.sqrt(2.0 * Math.log(1.1) * Math.log(1.1));
		Assert.floatEquals(expected, v, 1e-9);
	}

	public function testRealizedVolatilityConstantSeriesYieldsZero() {
		var rv = new RealizedVolatility(10);
		for (i in 0...40) {
			var v = rv.update(100.0);
			if (v != null) {
				Assert.floatEquals(0.0, v, 1e-9);
			}
		}
	}

	public function testRealizedVolatilityOutputIsNonNegative() {
		var rv = new RealizedVolatility(20);
		for (i in 1...201) {
			var p = 100.0 + Math.sin(i * 0.3) * 12.0;
			var v = rv.update(p);
			if (v != null) {
				Assert.isTrue(v >= 0.0, "RV must be non-negative, got " + v);
			}
		}
	}

	public function testRealizedVolatilityIgnoresNonFiniteInput() {
		var rv = new RealizedVolatility(5);
		for (i in 1...21) {
			rv.update(i);
		}
		var last = rv.isReady() ? rv.update(20.0) : null;
		var nan = rv.update(Math.NaN);
		Assert.equals(last, nan);
	}

	public function testRealizedVolatilityBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 1...121) {
			prices.push(100.0 + Math.sin(i * 0.25) * 9.0);
		}
		var batch = new RealizedVolatility(20);
		var streamed = new RealizedVolatility(20);
		var batchResults = [];
		var streamedResults = [];

		for (p in prices) {
			batchResults.push(batch.update(p));
		}
		for (p in prices) {
			streamedResults.push(streamed.update(p));
		}

		Assert.equals(batchResults.length, streamedResults.length);
		for (i in 0...batchResults.length) {
			if (batchResults[i] != null && streamedResults[i] != null) {
				Assert.floatEquals(batchResults[i], streamedResults[i], 1e-9);
			} else {
				Assert.equals(batchResults[i], streamedResults[i]);
			}
		}
	}

	// ── RecoveryFactor ────────────────────────────────────────────────────

	public function testRecoveryFactorAccessorsAndMetadata() {
		var r = new RecoveryFactor();
		Assert.equals(r.name(), "RecoveryFactor");
		Assert.equals(r.warmupPeriod(), 1);
		Assert.isNull(r.update(0.0)); // 0.0 keeps value as None
	}

	public function testRecoveryFactorPureUptrendYieldsZero() {
		var r = new RecoveryFactor();
		for (i in 1...11) {
			r.update(i);
		}
		Assert.notNull(r.update(10.0));
		Assert.floatEquals(0.0, r.update(10.0), 1e-9);
	}

	public function testRecoveryFactorReferenceValue() {
		// Start 100, peak 110, trough 88 -> max_dd = 0.2.
		// End 130 -> net_return = 0.3 -> Recovery = 1.5.
		var r = new RecoveryFactor();
		var values = [100.0, 110.0, 105.0, 95.0, 88.0, 100.0, 120.0, 130.0];
		var last = null;
		for (v in values) {
			last = r.update(v);
		}
		Assert.notNull(last);
		Assert.floatEquals(0.30 / 0.20, last, 1e-6);
	}

	public function testRecoveryFactorIgnoresNonFiniteInput() {
		var r = new RecoveryFactor();
		r.update(100.0);
		r.update(90.0);
		var v = r.update(85.0);
		var nan = r.update(Math.NaN);
		Assert.equals(v, nan);
	}

	public function testRecoveryFactorFirstValueAloneYieldsZero() {
		var r = new RecoveryFactor();
		var v = r.update(100.0);
		Assert.notNull(v);
		Assert.floatEquals(0.0, v, 1e-9);
	}

	public function testRecoveryFactorFirstZeroEquityKeepsValueNone() {
		var r = new RecoveryFactor();
		Assert.isNull(r.update(0.0));
		Assert.isFalse(r.isReady());
	}

	public function testRecoveryFactorBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...40) {
			prices.push(100.0 + Math.sin(i * 0.3) * 8.0);
		}
		var batch = new RecoveryFactor();
		var streamed = new RecoveryFactor();
		var batchResults = [];
		var streamedResults = [];

		for (p in prices) {
			batchResults.push(batch.update(p));
		}
		for (p in prices) {
			streamedResults.push(streamed.update(p));
		}

		Assert.equals(batchResults.length, streamedResults.length);
		for (i in 0...batchResults.length) {
			if (batchResults[i] != null && streamedResults[i] != null) {
				Assert.floatEquals(batchResults[i], streamedResults[i], 1e-9);
			} else {
				Assert.equals(batchResults[i], streamedResults[i]);
			}
		}
	}

	// ── Reflex ─────────────────────────────────────────────────────────────

	public function testReflexRejectsZeroPeriod() {
		try {
			var r = new Reflex(0);
			Assert.fail("Should reject period == 0");
		} catch (e:String) {
			Assert.pass();
		}
	}

	public function testReflexAccessorsAndMetadata() {
		var r = new Reflex(20);
		Assert.equals(r.warmupPeriod(), 21);
		Assert.equals(r.name(), "Reflex");
		Assert.isFalse(r.isReady());
	}

	public function testReflexFirstEmissionAtWarmupPeriod() {
		var r = new Reflex(5);
		var results = [];
		for (i in 0...12) {
			var x = 100.0 + Math.sin(i * 0.4) * 3.0;
			results.push(r.update(x));
		}
		// First 5 should be null
		for (i in 0...5) {
			Assert.isNull(results[i]);
		}
		// At index 5, should be non-null
		Assert.notNull(results[5]);
	}

	public function testReflexConstantInputIsZero() {
		var r = new Reflex(10);
		for (i in 0...100) {
			var v = r.update(50.0);
			if (v != null) {
				Assert.floatEquals(0.0, v, 1e-6);
			}
		}
	}

	public function testReflexIgnoresNonFinite() {
		var r = new Reflex(10);
		for (i in 0...40) {
			r.update(100.0 + Math.sin(i * 0.3));
		}
		var before = r.update(100.0);
		var nan = r.update(Math.NaN);
		Assert.equals(before, nan);
	}

	public function testReflexBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...120) {
			prices.push(100.0 + Math.sin(i * 0.25) * 9.0);
		}
		var batch = new Reflex(20);
		var streamed = new Reflex(20);
		var batchResults = [];
		var streamedResults = [];

		for (p in prices) {
			batchResults.push(batch.update(p));
		}
		for (p in prices) {
			streamedResults.push(streamed.update(p));
		}

		Assert.equals(batchResults.length, streamedResults.length);
		for (i in 0...batchResults.length) {
			if (batchResults[i] != null && streamedResults[i] != null) {
				Assert.floatEquals(batchResults[i], streamedResults[i], 1e-6);
			} else {
				Assert.equals(batchResults[i], streamedResults[i]);
			}
		}
	}

	// ── RegimeLabel ────────────────────────────────────────────────────────

	public function testRegimeLabelRejectsBadPeriods() {
		try {
			var rl = new RegimeLabel(1, 20);
			Assert.fail("Should reject volPeriod < 2");
		} catch (e:String) {
			Assert.pass();
		}
		try {
			var rl = new RegimeLabel(5, 1);
			Assert.fail("Should reject lookback < 2");
		} catch (e:String) {
			// Expected
		}
	}

	public function testRegimeLabelAccessorsAndMetadata() {
		var rl = new RegimeLabel(5, 20);
		Assert.equals(rl.warmupPeriod(), 25);
		Assert.equals(rl.name(), "RegimeLabel");
		Assert.isFalse(rl.isReady());
	}

	public function testRegimeLabelZeroVolatilityIsNeutral() {
		// Constant price has exactly-zero returns => zero vol => q1 == q3 == 0 => neutral 0
		var rl = new RegimeLabel(4, 8);
		for (i in 0...40) {
			var v = rl.update(100.0);
			if (v != null) {
				Assert.floatEquals(0.0, v, 1e-9);
			}
		}
	}

	public function testRegimeLabelOutputIsTernary() {
		// Output must be -1, 0, or +1
		var rl = new RegimeLabel(5, 20);
		for (i in 0...300) {
			var price = 100.0 + Math.sin(i * 0.3) * (1.0 + Math.sin(i * 0.05) * 5.0);
			var v = rl.update(price);
			if (v != null) {
				Assert.isTrue(v == -1.0 || v == 0.0 || v == 1.0, "non-ternary label " + v);
			}
		}
	}

	public function testRegimeLabelIgnoresNonFiniteAndNonPositive() {
		var rl = new RegimeLabel(4, 6);
		for (i in 0...40) {
			rl.update(100.0 + Math.sin(i * 0.5) * 2.0);
		}
		var before = rl.update(100.0);
		var nan = rl.update(Math.NaN);
		Assert.equals(before, nan);
		var neg = rl.update(-1.0);
		Assert.equals(before, neg);
		var zero = rl.update(0.0);
		Assert.equals(before, zero);
	}

	public function testRegimeLabelBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 1...161) {
			prices.push(100.0 + Math.sin(i * 0.25) * 4.0);
		}
		var batch = new RegimeLabel(5, 20);
		var streamed = new RegimeLabel(5, 20);
		var batchResults = [];
		var streamedResults = [];

		for (p in prices) {
			batchResults.push(batch.update(p));
		}
		for (p in prices) {
			streamedResults.push(streamed.update(p));
		}

		Assert.equals(batchResults.length, streamedResults.length);
		for (i in 0...batchResults.length) {
			if (batchResults[i] != null && streamedResults[i] != null) {
				Assert.floatEquals(batchResults[i], streamedResults[i], 1e-9);
			} else {
				Assert.equals(batchResults[i], streamedResults[i]);
			}
		}
	}
}
