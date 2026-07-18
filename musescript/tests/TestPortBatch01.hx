package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.Adl;
import musescript.indicators.lib.AdOscillator;
import musescript.indicators.lib.AccelerationBands;
import musescript.indicators.lib.AcceleratorOscillator;
import musescript.indicators.lib.AdaptiveCci;
import musescript.indicators.lib.AdvanceBlock;
import musescript.indicators.lib.AbandonedBaby;
import musescript.indicators.lib.AroonOscillator;
import musescript.indicators.lib.AwesomeOscillator;

/**
 * Batch 01: 8 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch01 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, volume:Float, i:Int):Bar {
		return bar(price, price, price, price, volume, i);
	}

	// ── ADL ──────────────────────────────────────────────────────────────────────

	public function testAdlReferenceValues() {
		// bar 1: close at high -> MFM = +1 -> MFV = +100; ADL = 100.
		// bar 2: h=12 l=8 c=9  -> MFM = ((9-8)-(12-9))/4 = -0.5 -> MFV = -100;
		//        ADL = 100 - 100 = 0.
		var bars = [
			bar(8.0, 10.0, 8.0, 10.0, 100.0, 0),
			bar(10.0, 12.0, 8.0, 9.0, 200.0, 1),
		];
		var ind = new Adl();
		var out = IndicatorBatch.run(ind, bars);
		Assert.floatEquals(100.0, out[0]);
		Assert.floatEquals(0.0, out[1]);
	}

	public function testAdlBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid, mid + 2.0, mid - 2.0, mid + 0.5, 10.0 + (i % 5), i);
		}];
		var a = new Adl(), b = new Adl();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── AdOscillator ─────────────────────────────────────────────────────────────

	public function testAdOscillatorFlatMarketOscillatesAtZero() {
		// A flat market never accumulates or distributes, so the oscillator sits at zero once warm.
		var bars = [for (i in 0...40) flatBar(50.0, 100.0, i)];
		var ind = new AdOscillator();
		var out = IndicatorBatch.run(ind, bars);
		for (i in 13...out.length) {
			Assert.notNull(out[i]);
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testAdOscillatorWarmupEmitsAtWarmupPeriod() {
		var bars = [for (i in 0...20) bar(100.0 + i, 100.0 + i + 2.0, 100.0 + i - 2.0, 100.0 + i, 100.0, i)];
		var ind = new AdOscillator();
		var out = IndicatorBatch.run(ind, bars);
		Assert.equals(14, ind.warmupPeriod());
		for (i in 0...13) Assert.isNull(out[i]);
		Assert.notNull(out[13]);
	}

	public function testAdOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...100) {
			var base = 100.0 + Math.sin(i * 0.2) * 5.0;
			bar(base, base + 1.5, base - 1.5, base + 0.4, 100.0, i);
		}];
		var a = new AdOscillator(), b = new AdOscillator();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── AccelerationBands ────────────────────────────────────────────────────────

	public function testAccelerationBandsReferenceValueSingleBar() {
		// Single bar with high=12, low=8, close=10, factor=0.5, period=1.
		// ratio = (12−8)/(12+8) = 0.2
		// raw_up = 12·(1+0.5·0.2) = 12·1.1 = 13.2
		// raw_lo = 8·(1−0.5·0.2) = 8·0.9 = 7.2
		// middle = SMA(close, 1) = 10
		var bars = [bar(10.0, 12.0, 8.0, 10.0, 1.0, 0)];
		var ind = new AccelerationBands(1, 0.5);
		var out = IndicatorBatch.run(ind, bars);
		var v = out[0];
		Assert.notNull(v);
		Assert.floatEquals(13.2, v.upper);
		Assert.floatEquals(10.0, v.middle);
		Assert.floatEquals(7.2, v.lower);
	}

	public function testAccelerationBandsFlatMarketCollapses() {
		// high == low so ratio = 0; all three collapse to same value.
		var bars = [for (i in 0...30) flatBar(10.0, 1.0, i)];
		var ind = new AccelerationBands(5, 0.5);
		var out = IndicatorBatch.run(ind, bars);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.floatEquals(10.0, last.middle);
		Assert.floatEquals(10.0, last.upper);
		Assert.floatEquals(10.0, last.lower);
	}

	public function testAccelerationBandsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) bar(i + 2.0, i + 2.0, i, i + 1.0, 1.0, i)];
		var a = new AccelerationBands(10, 0.5), b = new AccelerationBands(10, 0.5);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i].upper, streamed[i].upper);
			Assert.floatEquals(batched[i].middle, streamed[i].middle);
			Assert.floatEquals(batched[i].lower, streamed[i].lower);
		}
	}

	// ── AcceleratorOscillator ────────────────────────────────────────────────────

	public function testAcceleratorOscillatorConstantSeriesYieldsZero() {
		// A flat market gives AO = 0, so AC is 0 too.
		var bars = [for (i in 0...80) bar(10.0, 11.0, 9.0, 10.0, 1.0, i)];
		var ind = new AcceleratorOscillator(5, 34, 5);
		var out = IndicatorBatch.run(ind, bars);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testAcceleratorOscillatorFirstEmissionMatchesWarmupPeriod() {
		var bars = [for (i in 0...60) bar(10.0, 11.0, 9.0, 10.0, 1.0, i)];
		var ind = new AcceleratorOscillator(5, 34, 5);
		var out = IndicatorBatch.run(ind, bars);
		Assert.equals(38, ind.warmupPeriod());
		for (i in 0...37) Assert.isNull(out[i]);
		Assert.notNull(out[37]);
	}

	public function testAcceleratorOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...90) {
			var m = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(m, m + 1.5, m - 1.5, m + 0.5, 1.0, i);
		}];
		var a = new AcceleratorOscillator(5, 34, 5), b = new AcceleratorOscillator(5, 34, 5);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── AdaptiveCci ──────────────────────────────────────────────────────────────

	public function testAdaptiveCciFirstEmissionAtWarmupPeriod() {
		var bars = [for (i in 0...6) {
			var tp = 100.0 + i;
			bar(tp, tp, tp, tp, 1.0, i);
		}];
		var ind = new AdaptiveCci(4);
		var out = IndicatorBatch.run(ind, bars);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testAdaptiveCciUptrendIsPositive() {
		var bars = [for (i in 0...40) {
			var tp = 100.0 + i;
			bar(tp, tp, tp, tp, 1.0, i);
		}];
		var ind = new AdaptiveCci(10);
		var out = IndicatorBatch.run(ind, bars);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.isTrue(last > 0.0, "uptrend should give positive CCI");
	}

	public function testAdaptiveCciBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var tp = 100.0 + Math.sin(i * 0.25) * 9.0;
			bar(tp, tp, tp, tp, 1.0, i);
		}];
		var a = new AdaptiveCci(20), b = new AdaptiveCci(20);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── AdvanceBlock ─────────────────────────────────────────────────────────────

	public function testAdvanceBlockDetectsPattern() {
		// From the Rust fixture: 3 green bars with shrinking bodies and upper shadows.
		var bars = [
			bar(10.0, 13.1, 9.9, 13.0, 1.0, 0),
			bar(12.0, 14.3, 11.9, 14.0, 1.0, 1),
			bar(13.5, 15.0, 13.4, 14.5, 1.0, 2),
		];
		var ind = new AdvanceBlock();
		var out = IndicatorBatch.run(ind, bars);
		Assert.equals(0.0, out[0]); // too early
		Assert.equals(0.0, out[1]); // too early
		Assert.floatEquals(-1.0, out[2]); // pattern detected
	}

	public function testAdvanceBlockBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(m, m + 2.0, m - 2.0, m, 1.0, i);
		}];
		var a = new AdvanceBlock(), b = new AdvanceBlock();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── AbandonedBaby ────────────────────────────────────────────────────────────

	public function testAbandonedBabyDetectsBullishPattern() {
		// From the Rust fixture: red bar, doji gap below, green bar gaps above.
		var bars = [
			bar(20.0, 20.1, 14.9, 15.0, 1.0, 0),   // red
			bar(13.0, 13.1, 12.9, 13.0, 1.0, 1),   // doji
			bar(16.0, 18.1, 15.9, 18.0, 1.0, 2),   // green gap above
		];
		var ind = new AbandonedBaby();
		var out = IndicatorBatch.run(ind, bars);
		Assert.equals(0.0, out[0]); // too early
		Assert.equals(0.0, out[1]); // too early
		Assert.floatEquals(1.0, out[2]); // bullish pattern
	}

	public function testAbandonedBabyBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid, mid + 2.0, mid - 2.0, mid, 1.0, i);
		}];
		var a = new AbandonedBaby(), b = new AbandonedBaby();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── AroonOscillator ──────────────────────────────────────────────────────────

	public function testAroonOscillatorPureUptrendYieldsPlus100() {
		// Every bar a fresh high: AroonUp = 100, AroonDown = 0.
		var bars = [for (i in 1...16) {
			var p = 100.0 + i;
			bar(p, p + 1.0, p - 1.0, p, 1.0, i);
		}];
		var ind = new AroonOscillator(14);
		var out = IndicatorBatch.run(ind, bars);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(100.0, last);
	}

	public function testAroonOscillatorOutputStaysInBounds() {
		var bars = [for (i in 0...200) {
			var mid = 100.0 + Math.sin(i * 0.25) * 12.0;
			bar(mid, mid + 2.0, mid - 2.0, mid, 1.0, i);
		}];
		var ind = new AroonOscillator(14);
		var out = IndicatorBatch.run(ind, bars);
		for (v in out) if (v != null) Assert.isTrue(-100.0 <= v && v <= 100.0, "out of range: " + v);
	}

	public function testAroonOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid, mid + 2.0, mid - 2.0, mid, 1.0, i);
		}];
		var a = new AroonOscillator(14), b = new AroonOscillator(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
