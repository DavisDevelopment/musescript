package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.prim.Macd;
import musescript.indicators.prim.Macd.MacdOutput;
import musescript.indicators.prim.MaxDrawdown;
import musescript.indicators.prim.Mom;
import musescript.indicators.prim.Roc;
import musescript.indicators.prim.Vwap;
import musescript.indicators.prim.Vwap.RollingVwap;

/**
 * Batch 33: 5 Tier-P primitives (macd, max_drawdown, mom, roc, vwap) ported
 * from wickra-core. Known-value cases transcribed directly from the Rust
 * `#[cfg(test)]` fixture blocks in each .rs file; batch_equals_streaming
 * verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch33 extends Test {
	// Wickra VWAP test helper: c(price, volume) = Candle::new(p, p, p, p, v, 0)
	// → flat OHLC bar, typical price equals the price itself.
	static function c(price:Float, volume:Float, i:Int):Bar {
		return { open: price, high: price, low: price, close: price, volume: volume, time: (i : Float), index: i };
	}

	// ── MACD — macd.rs ───────────────────────────────────────────────────────

	public function testMacdRejectsFastGeqSlow() {
		try {
			new Macd(26, 12, 9);
			Assert.fail("Should reject fast > slow");
		} catch (e:Dynamic) Assert.pass();
		try {
			new Macd(12, 12, 9);
			Assert.fail("Should reject fast == slow");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testMacdRejectsZeroPeriods() {
		try {
			new Macd(0, 26, 9);
			Assert.fail("Should reject fast == 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new Macd(12, 0, 9);
			Assert.fail("Should reject slow == 0");
		} catch (e:Dynamic) Assert.pass();
		try {
			new Macd(12, 26, 0);
			Assert.fail("Should reject signal == 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testMacdAccessorsAndMetadata() {
		var m = new Macd(12, 26, 9);
		Assert.equals(12, m.fastPeriod);
		Assert.equals(26, m.slowPeriod);
		Assert.equals(9, m.signalPeriod);
		Assert.equals("MACD", m.name());
		Assert.isNull(m.value());
		for (i in 1...m.warmupPeriod() + 1) m.update(100.0 + i);
		Assert.notNull(m.value());
	}

	public function testMacdFirstEmissionMatchesWarmupPeriod() {
		var prices:Array<Float> = [for (i in 1...61) (i : Float)];
		var macd = Macd.classic();
		var out = IndicatorBatch.run(macd, prices);
		var warmup = macd.warmupPeriod();
		Assert.equals(26 + 9 - 1, warmup);
		for (i in 0...warmup - 1) Assert.isNull(out[i]);
		Assert.notNull(out[warmup - 1]);
	}

	public function testMacdHistogramEqualsMacdMinusSignal() {
		var prices:Array<Float> = [for (i in 1...81) i * 0.5];
		var macd = Macd.classic();
		for (v in IndicatorBatch.run(macd, prices)) {
			if (v != null) Assert.floatEquals(v.macd - v.signal, v.histogram);
		}
	}

	public function testMacdConstantSeriesYieldsZeroMacdEventually() {
		var macd = Macd.classic();
		var out = IndicatorBatch.run(macd, [for (_ in 0...200) 100.0]);
		var last:Null<MacdOutput> = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.floatEquals(0.0, last.macd);
		Assert.floatEquals(0.0, last.signal);
		Assert.floatEquals(0.0, last.histogram);
	}

	public function testMacdRisingSeriesMacdPositive() {
		var prices:Array<Float> = [for (i in 1...201) (i : Float)];
		var macd = Macd.classic();
		var out = IndicatorBatch.run(macd, prices);
		var last:Null<MacdOutput> = null;
		for (v in out) if (v != null) last = v;
		Assert.isTrue(last.macd > 0.0, "rising series must yield positive MACD");
	}

	public function testMacdIgnoresNonFiniteInput() {
		var macd = Macd.classic();
		IndicatorBatch.run(macd, [for (i in 1...81) (i : Float)]);
		var before = macd.value();
		Assert.notNull(before);
		// Non-finite inputs return the last value without advancing any EMA.
		var afterNan = macd.update(Math.NaN);
		Assert.floatEquals(before.macd, afterNan.macd);
		Assert.floatEquals(before.signal, afterNan.signal);
		Assert.floatEquals(before.histogram, afterNan.histogram);
		var afterInf = macd.update(Math.POSITIVE_INFINITY);
		Assert.floatEquals(before.macd, afterInf.macd);
		Assert.floatEquals(before.signal, afterInf.signal);
		Assert.floatEquals(before.histogram, afterInf.histogram);
	}

	public function testMacdResetClearsState() {
		var macd = Macd.classic();
		IndicatorBatch.run(macd, [for (i in 1...81) (i : Float)]);
		Assert.isTrue(macd.isReady());
		macd.reset();
		Assert.isTrue(!macd.isReady());
		Assert.isNull(macd.update(1.0));
	}

	public function testMacdBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 1...101) Math.cos(i * 0.4) * 10.0];
		var a = Macd.classic(), b = Macd.classic();
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
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

	// ── MaxDrawdown — max_drawdown.rs ────────────────────────────────────────

	public function testMaxDrawdownRejectsZeroPeriod() {
		try {
			new MaxDrawdown(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testMaxDrawdownAccessorsAndMetadata() {
		var mdd = new MaxDrawdown(10);
		Assert.equals(10, mdd.period);
		Assert.equals("MaxDrawdown", mdd.name());
		Assert.isTrue(Math.isNaN(mdd.value()));
		Assert.equals(10, mdd.warmupPeriod());
		for (v in 1...11) mdd.update((v : Float));
		Assert.isFalse(Math.isNaN(mdd.value()));
	}

	public function testMaxDrawdownPureUptrendYieldsZero() {
		var mdd = new MaxDrawdown(5);
		var out = IndicatorBatch.run(mdd, [for (i in 1...21) (i : Float)]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testMaxDrawdownReferenceDrawdown() {
		// Window [100, 120, 90]: peak 120, trough 90 -> 25% drawdown.
		var mdd = new MaxDrawdown(3);
		var out = IndicatorBatch.run(mdd, [100.0, 120.0, 90.0]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.floatEquals(0.25, out[2]);
	}

	public function testMaxDrawdownConstantSeriesYieldsZero() {
		var mdd = new MaxDrawdown(4);
		var out = IndicatorBatch.run(mdd, [for (_ in 0...12) 50.0]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testMaxDrawdownIgnoresNonFiniteInput() {
		var mdd = new MaxDrawdown(3);
		IndicatorBatch.run(mdd, [100.0, 90.0, 80.0]);
		var last = mdd.value();
		Assert.floatEquals(last, mdd.update(Math.NaN));
		Assert.floatEquals(last, mdd.update(Math.POSITIVE_INFINITY));
	}

	public function testMaxDrawdownResetClearsState() {
		var mdd = new MaxDrawdown(3);
		IndicatorBatch.run(mdd, [100.0, 90.0, 80.0]);
		Assert.isTrue(mdd.isReady());
		mdd.reset();
		Assert.isTrue(!mdd.isReady());
		Assert.isNull(mdd.update(100.0));
	}

	public function testMaxDrawdownBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 10.0];
		var a = new MaxDrawdown(10), b = new MaxDrawdown(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	public function testMaxDrawdownNonPositivePeakYieldsZero() {
		// All-zero stream: peak is 0, division skipped, result stays 0.
		var mdd = new MaxDrawdown(3);
		var out = IndicatorBatch.run(mdd, [for (_ in 0...6) 0.0]);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	// ── MOM — mom.rs ─────────────────────────────────────────────────────────

	public function testMomRejectsZeroPeriod() {
		try {
			new Mom(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testMomAccessorsAndMetadata() {
		var m = new Mom(5);
		Assert.equals(5, m.period);
		Assert.equals("MOM", m.name());
		Assert.isTrue(Math.isNaN(m.value()));
		for (i in 1...7) m.update((i : Float));
		Assert.isFalse(Math.isNaN(m.value()));
	}

	public function testMomReferenceValues() {
		// MOM(3): price_t − price_{t-3}.
		var mom = new Mom(3);
		var out = IndicatorBatch.run(mom, [1.0, 2.0, 3.0, 4.0, 7.0]);
		Assert.equals(4, mom.warmupPeriod());
		Assert.isNull(out[0]);
		Assert.isNull(out[2]);
		Assert.floatEquals(4.0 - 1.0, out[3]);
		Assert.floatEquals(7.0 - 2.0, out[4]);
	}

	public function testMomConstantSeriesYieldsZero() {
		var mom = new Mom(5);
		var out = IndicatorBatch.run(mom, [for (_ in 0...20) 10.0]);
		for (i in 5...out.length) if (out[i] != null) Assert.floatEquals(0.0, out[i]);
	}

	public function testMomIgnoresNonFiniteInput() {
		var mom = new Mom(3);
		var out = IndicatorBatch.run(mom, [1.0, 2.0, 3.0, 4.0]);
		var ready = out[3];
		Assert.notNull(ready);
		Assert.floatEquals(ready, mom.update(Math.NaN));
		Assert.floatEquals(ready, mom.update(Math.POSITIVE_INFINITY));
		// Window untouched: the next finite input still references price 2.
		Assert.floatEquals(10.0 - 2.0, mom.update(10.0));
	}

	public function testMomResetClearsState() {
		var mom = new Mom(3);
		IndicatorBatch.run(mom, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(mom.isReady());
		mom.reset();
		Assert.isTrue(!mom.isReady());
		Assert.isNull(mom.update(1.0));
	}

	public function testMomBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 1...41) i * 1.5];
		var a = new Mom(7), b = new Mom(7);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── ROC — roc.rs ─────────────────────────────────────────────────────────

	public function testRocRejectsZeroPeriod() {
		try {
			new Roc(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRocAccessorsAndMetadata() {
		var roc = new Roc(5);
		Assert.equals(5, roc.period);
		Assert.equals(6, roc.warmupPeriod());
		Assert.equals("ROC", roc.name());
	}

	public function testRocConstantSeriesYieldsZero() {
		var roc = new Roc(5);
		var out = IndicatorBatch.run(roc, [for (_ in 0...20) 10.0]);
		for (i in 5...out.length) if (out[i] != null) Assert.floatEquals(0.0, out[i]);
	}

	public function testRocKnownValue() {
		// ROC(3) where prev = 100, now = 110 -> 10%
		var roc = new Roc(3);
		var out = IndicatorBatch.run(roc, [100.0, 105.0, 108.0, 110.0]);
		Assert.floatEquals(10.0, out[3]);
	}

	public function testRocZeroPreviousPriceYieldsZero() {
		// Divide-by-zero guard: front of the window exactly 0.0 -> 0.0, not NaN.
		var roc = new Roc(3);
		var out = IndicatorBatch.run(roc, [0.0, 5.0, 7.0, 9.0]);
		Assert.notNull(out[3]);
		Assert.floatEquals(0.0, out[3]);
	}

	public function testRocIgnoresNonFiniteInput() {
		var roc = new Roc(3);
		var out = IndicatorBatch.run(roc, [100.0, 105.0, 108.0, 110.0]);
		var ready = out[3];
		Assert.notNull(ready);
		// Non-finite inputs return the last value without sliding the window.
		Assert.floatEquals(ready, roc.update(Math.NaN));
		Assert.floatEquals(ready, roc.update(Math.POSITIVE_INFINITY));
		// Window untouched: the next finite input still references prev = 105.
		Assert.floatEquals((115.0 - 105.0) / 105.0 * 100.0, roc.update(115.0));
	}

	public function testRocResetClearsState() {
		var roc = new Roc(5);
		IndicatorBatch.run(roc, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
		Assert.isTrue(roc.isReady());
		roc.reset();
		Assert.isTrue(!roc.isReady());
	}

	public function testRocBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 1...31) i * 2.0];
		var a = new Roc(5), b = new Roc(5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── VWAP (cumulative + rolling) — vwap.rs ────────────────────────────────

	public function testVwapCumulativeEqualVolumesEqualsMean() {
		var candles = [c(10.0, 1.0, 0), c(20.0, 1.0, 1), c(30.0, 1.0, 2)];
		var v = new Vwap();
		var out = IndicatorBatch.run(v, candles);
		Assert.floatEquals(20.0, out[2]);
	}

	public function testVwapCumulativeValueAfterUpdate() {
		var v = new Vwap();
		// typical_price of a flat OHLC bar equals the price itself.
		v.update(c(42.0, 5.0, 0));
		Assert.floatEquals(42.0, v.value());
	}

	public function testVwapCumulativeZeroVolumeFirstCandleReturnsNull() {
		var v = new Vwap();
		Assert.isNull(v.update(c(42.0, 0.0, 0)));
		Assert.isTrue(!v.isReady());
		// Adding a non-zero candle afterwards still works as expected.
		Assert.floatEquals(10.0, v.update(c(10.0, 4.0, 1)));
	}

	public function testVwapCumulativeMetadata() {
		var v = new Vwap();
		Assert.equals(1, v.warmupPeriod());
		Assert.equals("VWAP", v.name());
	}

	public function testVwapCumulativeWeighted() {
		// Two candles: 10@1 and 20@3 -> (10*1 + 20*3) / (1+3) = 70/4 = 17.5
		var candles = [c(10.0, 1.0, 0), c(20.0, 3.0, 1)];
		var v = new Vwap();
		var out = IndicatorBatch.run(v, candles);
		Assert.floatEquals(17.5, out[1]);
	}

	public function testVwapCumulativeResetClearsState() {
		var candles = [c(10.0, 1.0, 0), c(20.0, 1.0, 1), c(30.0, 1.0, 2)];
		var v = new Vwap();
		IndicatorBatch.run(v, candles);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isTrue(Math.isNaN(v.value()));
	}

	public function testVwapBatchEqualsStreamingCumulative() {
		var candles = [for (i in 1...20) c((i : Float), 1.0, i)];
		var a = new Vwap(), b = new Vwap();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	public function testRollingVwapRejectsZeroPeriod() {
		try {
			new RollingVwap(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) Assert.pass();
	}

	public function testRollingVwapAccessorsAndMetadata() {
		var v = new RollingVwap(7);
		Assert.equals(7, v.period);
		Assert.equals(7, v.warmupPeriod());
		Assert.equals("RollingVWAP", v.name());
	}

	public function testRollingVwapWindowSlides() {
		var candles = [c(10.0, 1.0, 0), c(20.0, 1.0, 1), c(30.0, 1.0, 2), c(40.0, 1.0, 3)];
		var v = new RollingVwap(3);
		var out = IndicatorBatch.run(v, candles);
		Assert.isNull(out[1]);
		// index 2 -> (10+20+30)/3 = 20
		Assert.floatEquals(20.0, out[2]);
		// index 3 -> (20+30+40)/3 = 30
		Assert.floatEquals(30.0, out[3]);
	}

	public function testRollingVwapBatchEqualsStreaming() {
		var candles = [for (i in 1...30) c((i : Float), (i % 5 + 1 : Float), i)];
		var a = new RollingVwap(10), b = new RollingVwap(10);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	public function testRollingVwapResetClearsState() {
		var candles = [for (i in 1...11) c((i : Float), 1.0, i)];
		var v = new RollingVwap(5);
		IndicatorBatch.run(v, candles);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(candles[0]));
	}
}
