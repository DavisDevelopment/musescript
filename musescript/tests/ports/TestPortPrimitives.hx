package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.prim.Wma;
import musescript.indicators.prim.Rsi;
import musescript.indicators.prim.Atr;

/**
 * prim/ primitives — the streaming building blocks composites reuse (Wilder
 * RSI/ATR, WMA). Known-value cases transcribed from wickra-core's OWN Rust
 * `#[cfg(test)]` fixtures (same reference numbers upstream checks itself
 * against, not re-derived); `batch_equals_streaming` is Wickra's own name
 * for the batch==streaming property. See musescript/indicators/PORTING.md.
 */
class TestPortPrimitives extends Test {
	// Wickra ATR test helper: c(h, l, cl) = Candle::new(cl, h, l, cl, 1, 0)
	// → open=close=cl, high=h, low=l.
	static function c(h:Float, l:Float, cl:Float, i:Int):Bar {
		return { open: cl, high: h, low: l, close: cl, volume: 1.0, time: (i : Float), index: i };
	}

	// ── WMA — wma.rs ──────────────────────────────────────────────────────────

	public function testWmaKnownValuesPeriod3() {
		// weights [1,2,3], total 6; inputs 1,2,3 → (1+4+9)/6 = 14/6.
		var w = new Wma(3);
		Assert.isNull(w.update(1.0));
		Assert.isNull(w.update(2.0));
		Assert.floatEquals(14.0 / 6.0, w.update(3.0));
	}

	public function testWmaKnownValuesPeriod4() {
		// weights [1,2,3,4], total 10; inputs 1,2,3,4 → 30/10 = 3.0.
		var w = new Wma(4);
		var v = IndicatorBatch.run(w, [1.0, 2.0, 3.0, 4.0]);
		Assert.floatEquals(3.0, v[3]);
	}

	public function testWmaPeriodOneIsPassThrough() {
		var w = new Wma(1);
		Assert.floatEquals(5.5, w.update(5.5));
		Assert.floatEquals(7.5, w.update(7.5));
	}

	public function testWmaBatchEqualsStreaming() {
		var xs:Array<Float> = [for (i in 0...40) 50.0 + Math.sin(i * 0.3) * 8.0];
		var a = new Wma(9), b = new Wma(9);
		var batched = IndicatorBatch.run(a, xs);
		var streamed = [for (x in xs) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── RSI (Wilder) — rsi.rs ────────────────────────────────────────────────

	public function testRsiPureUptrendYields100() {
		var prices:Array<Float> = [for (i in 0...40) 10.0 + i];
		var r = new Rsi(14);
		var out = IndicatorBatch.run(r, prices);
		for (v in out) if (v != null) Assert.floatEquals(100.0, v);
	}

	public function testRsiPureDowntrendYields0() {
		var prices:Array<Float> = [for (i in 0...40) 100.0 - i];
		var r = new Rsi(14);
		var out = IndicatorBatch.run(r, prices);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testRsiFlatSeriesYields50() {
		var prices:Array<Float> = [for (_ in 0...40) 10.0];
		var r = new Rsi(14);
		var out = IndicatorBatch.run(r, prices);
		for (v in out) if (v != null) Assert.floatEquals(50.0, v);
	}

	public function testRsiFirstValueAtIndexPeriod() {
		// warmup = period + 1; first non-null at index `period`.
		var r = new Rsi(5);
		var out = IndicatorBatch.run(r, [for (i in 0...10) 10.0 + i]);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
		Assert.equals(6, r.warmupPeriod());
	}

	public function testRsiBatchEqualsStreaming() {
		var prices:Array<Float> = [for (i in 0...60) 50.0 + Math.sin(i * 0.25) * 10.0];
		var a = new Rsi(14), b = new Rsi(14);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── ATR (Wilder) — atr.rs ────────────────────────────────────────────────

	public function testAtrGapUpUsesHighMinusPrevClose() {
		// prev close 5; current H=10 L=9 → TR = max(1, |10-5|, |9-5|) = 5.
		// Seed(2) = (TR1=H1-L1=2, TR2=5) mean = 3.5.
		var candles = [c(6.0, 4.0, 5.0, 0), c(10.0, 9.0, 9.5, 1)];
		var atr = new Atr(2);
		var out = IndicatorBatch.run(atr, candles);
		Assert.floatEquals(3.5, out[1]);
	}

	public function testAtrConstantRangeYieldsConstantAtr() {
		// Every bar range 2 → ATR converges to (and stays at) 2.
		var candles = [for (i in 0...20) c(12.0, 10.0, 11.0, i)];
		var atr = new Atr(5);
		for (v in IndicatorBatch.run(atr, candles)) if (v != null) Assert.floatEquals(2.0, v);
	}

	public function testAtrNeverNegative() {
		var candles = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			c(base + 1.0, base - 1.0, base, i);
		}];
		var atr = new Atr(14);
		for (v in IndicatorBatch.run(atr, candles)) if (v != null) Assert.isTrue(v >= 0.0);
	}

	public function testAtrBatchEqualsStreaming() {
		var candles = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.4) * 6.0;
			c(base + 1.5, base - 1.5, base + 0.3, i);
		}];
		var a = new Atr(14), b = new Atr(14);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
