package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.DemandIndex;
import musescript.indicators.lib.DumplingTop;
import musescript.indicators.lib.EhlersStochastic;
import musescript.indicators.lib.DoubleTopBottom;

/**
 * Batch 29: 3 indicators + 1 prim ported from wickra-core.
 * - DemandIndex (Candle -> f64)
 * - DumplingTop (Candle -> f64)
 * - EhlersStochastic (f64 -> f64) + RoofingFilter prim
 *
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch29 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, volume:Float, i:Int):Bar {
		return bar(price, price, price, price, volume, i);
	}

	// ── DemandIndex ──────────────────────────────────────────────────────────────

	public function testDemandIndexAccessorsAndMetadata() {
		var di = new DemandIndex(10);
		Assert.equals(10, di.period);
		Assert.equals("DI", di.name());
		Assert.equals(11, di.warmupPeriod());
	}

	public function testDemandIndexConstantSeriesYieldsZero() {
		// No close change -> pressure = 0 on every bar -> EMA stays at 0.
		var bars = [for (i in 0...40) flatBar(10.0, 100.0, i)];
		var di = new DemandIndex(5);
		var out = IndicatorBatch.run(di, bars);
		for (v in out) {
			if (v != null) {
				Assert.floatEquals(0.0, v, 1e-10);
			}
		}
	}

	public function testDemandIndexRisingSeriesYieldsPositiveSignal() {
		// Strictly rising closes on constant volume -> pressure is positive every
		// bar -> smoothed DI must end up strictly positive.
		var bars = [for (i in 0...40) {
			var f = (i : Float);
			bar(100.0 + f, 101.0 + f, 99.0 + f, 100.5 + f, 100.0, i);
		}];
		var di = new DemandIndex(5);
		var out = IndicatorBatch.run(di, bars);
		var last = null;
		for (i in (out.length - 1)...out.length) {
			if (out[i] != null) {
				last = out[i];
			}
		}
		Assert.isTrue(last > 0.0, "rising series must yield positive DI");
	}

	public function testDemandIndexFallingSeriesYieldsNegativeSignal() {
		var bars = [for (i in 0...40) {
			var f = (i : Float);
			bar(200.0 - f, 201.0 - f, 199.0 - f, 199.5 - f, 100.0, i);
		}];
		var di = new DemandIndex(5);
		var out = IndicatorBatch.run(di, bars);
		var last = null;
		for (i in (out.length - 1)...out.length) {
			if (out[i] != null) {
				last = out[i];
			}
		}
		Assert.isTrue(last < 0.0, "falling series must yield negative DI");
	}

	public function testDemandIndexBatchEqualsStreaming() {
		var bars = [for (i in 0...100) {
			var f = (i : Float);
			var mid = 100.0 + Math.sin(f * 0.2) * 5.0;
			bar(mid, mid + 1.5, mid - 1.5, mid + 0.3, 80.0 + (i % 5), i);
		}];
		var a = new DemandIndex(10);
		var b = new DemandIndex(10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── DumplingTop ──────────────────────────────────────────────────────────────

	public function testDumplingTopAccessorsAndMetadata() {
		var d = new DumplingTop(9);
		Assert.equals(9, d.period);
		Assert.equals(9, d.warmupPeriod());
		Assert.equals("DumplingTop", d.name());
		Assert.isFalse(d.isReady());
	}

	public function testDumplingTopFirstEmissionAtWarmupPeriod() {
		var c = [
			flatBar(100.0, 1000.0, 0),
			flatBar(101.0, 1000.0, 1),
			flatBar(102.0, 1000.0, 2),
			flatBar(101.0, 1000.0, 3),
			flatBar(99.0, 1000.0, 4),
			flatBar(98.0, 1000.0, 5),
		];
		var d = new DumplingTop(5);
		var out = IndicatorBatch.run(d, c);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testDumplingTopRoundedTopThenBreakdownSignals() {
		// closes = [100, 102, 104, 105, 104, 102, 99, 97, 95]
		// max at index 3 (middle), last close 95 < first close 100 -> dome + breakdown -> -1.0
		var closes = [100.0, 102.0, 104.0, 105.0, 104.0, 102.0, 99.0, 97.0, 95.0];
		var c = [for (x in closes) flatBar(x, 1000.0, 0)];
		var d = new DumplingTop(9);
		var out = IndicatorBatch.run(d, c);
		var last = out[out.length - 1];
		Assert.equals(-1.0, last);
	}

	public function testDumplingTopOneSidedRiseIsZero() {
		// Monotonically rising: max at end (not middle) -> no dome -> 0.0
		var c = [for (i in 0...9) flatBar(100.0 + i, 1000.0, i)];
		var d = new DumplingTop(9);
		var out = IndicatorBatch.run(d, c);
		var last = out[out.length - 1];
		Assert.equals(0.0, last);
	}

	public function testDumplingTopNoBreakdownIsZero() {
		// closes = [100, 102, 104, 105, 104, 103, 102, 101, 100.5]
		// Has dome but last close (100.5) >= first close (100), so no breakdown -> 0.0
		var closes = [100.0, 102.0, 104.0, 105.0, 104.0, 103.0, 102.0, 101.0, 100.5];
		var c = [for (x in closes) flatBar(x, 1000.0, 0)];
		var d = new DumplingTop(9);
		var out = IndicatorBatch.run(d, c);
		var last = out[out.length - 1];
		Assert.equals(0.0, last);
	}

	public function testDumplingTopBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var price = 100.0 + Math.sin(i * 0.3) * 5.0;
			flatBar(price, 1000.0, i);
		}];
		var a = new DumplingTop(9);
		var b = new DumplingTop(9);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── EhlersStochastic ─────────────────────────────────────────────────────────

	public function testEhlersStochasticAccessorsAndMetadata() {
		var es = new EhlersStochastic(20);
		Assert.equals(20, es.period);
		// warmup = period + roofing.warmupPeriod() = 20 + 2 = 22
		Assert.equals(22, es.warmupPeriod());
		Assert.equals("EhlersStochastic", es.name());
		Assert.isFalse(es.isReady());
	}

	public function testEhlersStochasticOutputBoundedInUnitInterval() {
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.3) * 5.0];
		var es = new EhlersStochastic(20);
		var out = IndicatorBatch.run(es, prices);
		for (v in out) {
			if (v != null) {
				Assert.isTrue(-1.0 <= v && v <= 1.0, "value out of band: " + v);
			}
		}
	}

	public function testEhlersStochasticFlatWindowEmitsZero() {
		// A constant series has zero high-pass output, so max == min and
		// the range > 0.0 guard takes the 0.0 fallback.
		var prices = [for (i in 0...150) 100.0];
		var es = new EhlersStochastic(20);
		var out = IndicatorBatch.run(es, prices);
		for (v in out) {
			if (v != null) {
				Assert.floatEquals(0.0, v, 1e-10);
			}
		}
	}

	public function testEhlersStochasticBatchEqualsStreaming() {
		var prices = [for (i in 0...150) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new EhlersStochastic(20);
		var b = new EhlersStochastic(20);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── DoubleTopBottom ──────────────────────────────────────────────────────────

	public function testDoubleTopBottomAccessorsAndMetadata() {
		var indicator = new DoubleTopBottom();
		Assert.equals("DoubleTopBottom", indicator.name());
		Assert.equals(5, indicator.warmupPeriod());
		Assert.isFalse(indicator.isReady());
	}

	public function testDoubleTopBottomAlwaysReturnsValue() {
		// Double top/bottom never returns null (candlestick-pattern convention):
		// every bar gets 0.0 or a pattern signal (-1.0 or 1.0).
		var bars = [for (i in 0...20) {
			var base = 100.0 + Math.sin(i * 0.3) * 10.0;
			bar(base, base + 1.0, base - 1.0, base, 100.0, i);
		}];
		var ind = new DoubleTopBottom();
		var out = IndicatorBatch.run(ind, bars);
		// Every bar should return a non-null value
		for (v in out) {
			Assert.notNull(v);
		}
	}

	public function testDoubleTopBottomOutputIsZeroOrSignal() {
		// Outputs must be in {-1.0, 0.0, 1.0}: double top (-1), double bottom (1), or no pattern (0).
		var bars = [for (i in 0...30) {
			var base = 100.0 + Math.sin(i * 0.2) * 8.0;
			bar(base, base + 2.0, base - 2.0, base + 0.5, 100.0, i);
		}];
		var ind = new DoubleTopBottom();
		var out = IndicatorBatch.run(ind, bars);
		for (v in out) {
			var isValid = (v == -1.0 || v == 0.0 || v == 1.0);
			Assert.isTrue(isValid, "value must be -1, 0, or 1 but got " + v);
		}
	}

	public function testDoubleTopBottomBatchEqualsStreaming() {
		var bars = [
			bar(120.0, 119.88, 120.0, 120.0, 1.0, 0),
			bar(114.0, 119.88, 114.0, 114.0, 1.0, 1),
			bar(105.0, 105.0, 100.0, 105.0, 1.0, 2),
			bar(120.0, 120.0, 105.0, 120.0, 1.0, 3),
			bar(100.0, 120.0, 100.0, 100.0, 1.0, 4),
			bar(110.0, 110.0, 100.0, 110.0, 1.0, 5),
		];
		var a = new DoubleTopBottom();
		var b = new DoubleTopBottom();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
