package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.EmpiricalModeDecomposition;
import musescript.indicators.lib.Equivolume;
import musescript.indicators.lib.EvenBetterSinewave;
import musescript.indicators.lib.FibArcs;
import musescript.indicators.lib.FibChannel;

/**
 * Batch 30: 5 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch30 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, volume:Float, i:Int):Bar {
		return bar(price, price, price, price, volume, i);
	}

	// ── EmpiricalModeDecomposition ─────────────────────────────────────────

	public function testEmpiricalModeDecompositionAccessorsAndMetadata() {
		var emd = new EmpiricalModeDecomposition(20, 0.5);
		// Rust's own fixture only asserts warmup_period() >= 1 (it's bp_history_len =
		// round(period*fraction), not period itself) -- matching that, not inventing "== 20".
		Assert.isTrue(emd.warmupPeriod() >= 1);
		Assert.equals("EmpiricalModeDecomposition", emd.name());
		Assert.isFalse(emd.isReady());
	}

	public function testEmpiricalModeDecompositionBatchEqualsStreaming() {
		var prices = [for (i in 0...200)
			100.0 + Math.sin(i * 0.2) * 5.0
		];

		var a = new EmpiricalModeDecomposition(20, 0.5);
		var b = new EmpiricalModeDecomposition(20, 0.5);
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

	public function testEmpiricalModeDecompositionIgnoresNonFiniteInput() {
		var emd = new EmpiricalModeDecomposition(20, 0.5);
		var prices = [for (i in 0...200)
			100.0 + Math.sin(i * 0.3) * 5.0
		];

		IndicatorBatch.run(emd, prices);
		var before = emd.update(prices[199]);
		Assert.notNull(before);
		var afterNan = emd.update(Math.NaN);
		Assert.floatEquals(before, afterNan);
	}

	public function testEmpiricalModeDecompositionResetClearsState() {
		var prices = [for (i in 0...200)
			100.0 + Math.sin(i * 0.3) * 5.0
		];

		var emd = new EmpiricalModeDecomposition(20, 0.5);
		IndicatorBatch.run(emd, prices);
		Assert.isTrue(emd.isReady());
		emd.reset();
		Assert.isFalse(emd.isReady());
	}

	// ── Equivolume ────────────────────────────────────────────────────────────

	public function testEquivolumeAccessorsAndMetadata() {
		var e = new Equivolume(14);
		Assert.equals(14, e.warmupPeriod());
		Assert.equals("Equivolume", e.name());
		Assert.isFalse(e.isReady());
	}

	public function testEquivolumeHeightIsRange() {
		var bars = [
			bar(102.5, 105.0, 100.0, 102.5, 1000.0, 0),
			bar(102.5, 105.0, 100.0, 102.5, 1000.0, 1)
		];
		var e = new Equivolume(2);
		var out = IndicatorBatch.run(e, bars);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(5.0, last.height, 1e-9);
	}

	public function testEquivolumeAverageVolumeWidthIsOne() {
		var bars = [for (i in 0...6)
			bar(102.0, 102.0, 98.0, 102.0, 1000.0, i)
		];
		var e = new Equivolume(3);
		var out = IndicatorBatch.run(e, bars);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(1.0, last.width, 1e-9);
	}

	public function testEquivolumeHeavyBarIsWide() {
		var bars = [
			bar(102.0, 102.0, 98.0, 102.0, 1000.0, 0),
			bar(102.0, 102.0, 98.0, 102.0, 1000.0, 1),
			bar(102.0, 102.0, 98.0, 102.0, 4000.0, 2),
		];
		var e = new Equivolume(3);
		var out = IndicatorBatch.run(e, bars);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(last.width > 1.0, "heavy bar should be wider than average");
	}

	public function testEquivolumeZeroVolumeGivesZeroWidth() {
		var bars = [
			bar(11.0, 11.0, 9.0, 11.0, 0.0, 0),
			bar(12.0, 12.0, 10.0, 12.0, 0.0, 1),
			bar(13.0, 13.0, 11.0, 13.0, 0.0, 2),
		];
		var e = new Equivolume(2);
		var out = IndicatorBatch.run(e, bars);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.equals(0.0, last.width);
	}

	public function testEquivolumeResetClearsState() {
		var bars = [for (i in 0...6)
			bar(102.0, 102.0, 98.0, 102.0, 1000.0, i)
		];
		var e = new Equivolume(3);
		IndicatorBatch.run(e, bars);
		Assert.isTrue(e.isReady());
		e.reset();
		Assert.isFalse(e.isReady());
	}

	public function testEquivoluemBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.25) * 5.0;
			bar(mid, mid + 5.0, mid - 5.0, mid, 1000.0 + i, i);
		}];
		var a = new Equivolume(14), b = new Equivolume(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];

		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].height, streamed[i].height);
				Assert.floatEquals(batched[i].width, streamed[i].width);
			}
		}
	}

	// ── EvenBetterSinewave ────────────────────────────────────────────────────

	public function testEvenBetterSinewaveAccessorsAndMetadata() {
		var e = new EvenBetterSinewave(40, 10);
		Assert.equals(3, e.warmupPeriod());
		Assert.equals("EvenBetterSinewave", e.name());
		Assert.isFalse(e.isReady());
	}

	public function testEvenBetterSinewaveFirstEmissionAtWarmupPeriod() {
		var prices = [for (i in 0...12)
			100.0 + Math.sin(i * 0.5) * 3.0
		];
		var e = new EvenBetterSinewave(40, 10);
		var out = IndicatorBatch.run(e, prices);
		for (i in 0...2) Assert.isNull(out[i]);
		Assert.notNull(out[2]);
	}

	public function testEvenBetterSinewaveOutputInRange() {
		var prices = [for (i in 0...400)
			100.0 + Math.sin(Math.PI * 2.0 * i / 30.0) * 5.0
		];
		var e = new EvenBetterSinewave(40, 10);
		var out = IndicatorBatch.run(e, prices);
		for (v in out) {
			if (v != null) {
				Assert.isTrue(-1.0 <= v && v <= 1.0, "EBSW out of range: " + v);
			}
		}
	}

	public function testEvenBetterSinewaveCyclicInputSwingsBothSigns() {
		var prices = [for (i in 0...400)
			100.0 + Math.sin(Math.PI * 2.0 * i / 30.0) * 5.0
		];
		var e = new EvenBetterSinewave(30, 8);
		var out = IndicatorBatch.run(e, prices);
		var filtered = [for (i in 100...out.length) if (out[i] != null) out[i]];
		var hasPositive = false, hasNegative = false;
		for (v in filtered) {
			if (v > 0.5) hasPositive = true;
			if (v < -0.5) hasNegative = true;
		}
		Assert.isTrue(hasPositive);
		Assert.isTrue(hasNegative);
	}

	public function testEvenBetterSinewaveIgnoresNonFinite() {
		var e = new EvenBetterSinewave(40, 10);
		var prices = [for (i in 0...40)
			100.0 + Math.sin(i * 0.3) * 1.0
		];
		IndicatorBatch.run(e, prices);
		var before = e.update(100.0);
		Assert.notNull(before);
		var afterNan = e.update(Math.NaN);
		Assert.equals(before, afterNan);
	}

	public function testEvenBetterSinewaveResetClearsState() {
		var prices = [for (i in 0...40)
			100.0 + Math.sin(i * 0.3) * 1.0
		];
		var e = new EvenBetterSinewave(40, 10);
		IndicatorBatch.run(e, prices);
		Assert.isTrue(e.isReady());
		e.reset();
		Assert.isFalse(e.isReady());
	}

	public function testEvenBetterSinewaveBatchEqualsStreaming() {
		var prices = [for (i in 0...120)
			100.0 + Math.sin(i * 0.25) * 9.0
		];
		var a = new EvenBetterSinewave(40, 10), b = new EvenBetterSinewave(40, 10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];

		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── FibArcs ───────────────────────────────────────────────────────────────

	static function c(high:Float, low:Float, ts:Int):Bar {
		return bar(low, high, low, low, 1.0, ts);
	}

	static function downLeg():Array<Bar> {
		return [
			c(200.0, 199.0, 0),
			c(190.0, 160.0, 1),   // confirm high @200
			c(150.0, 100.0, 2),   // extend low to 100 (bar 2)
			c(110.0, 105.0, 3),   // confirm low @100 -> two pivots
		];
	}

	public function testFibArcsAccessorsAndMetadata() {
		var indicator = new FibArcs();
		Assert.equals("FibArcs", indicator.name());
		Assert.equals(2, indicator.warmupPeriod());
		Assert.isFalse(indicator.isReady());
	}

	public function testFibArcsNoOutputBeforeTwoPivots() {
		var indicator = new FibArcs();
		var outputs = [
			indicator.update(c(200.0, 199.0, 0)),
			indicator.update(c(190.0, 150.0, 1))
		];
		for (o in outputs) Assert.isNull(o);
		Assert.isFalse(indicator.isReady());
	}

	public function testFibArcsCurveBackTowardSwingEnd() {
		var indicator = new FibArcs();
		var last = null;
		for (candle in downLeg()) {
			last = indicator.update(candle);
		}
		Assert.notNull(last);
		Assert.isTrue(indicator.isReady());

		// u = 0.5 -> curve = sqrt(0.75); arc(r) = 100 + 100 * r * curve
		var curve = Math.sqrt(0.75);
		Assert.floatEquals(100.0 + 100.0 * 0.382 * curve, last.arc382, 1e-6);
		Assert.floatEquals(100.0 + 100.0 * 0.5 * curve, last.arc500, 1e-6);
		Assert.floatEquals(100.0 + 100.0 * 0.618 * curve, last.arc618, 1e-6);
	}

	public function testFibArcsClampsToZeroBeyondOneLegWidth() {
		var indicator = new FibArcs();
		for (candle in downLeg()) {
			indicator.update(candle);
		}
		// Feed flat bars extending past the pivot
		var last = null;
		for (ts in 4...12) {
			last = indicator.update(c(108.0, 106.0, ts));
		}
		Assert.notNull(last);
		Assert.floatEquals(100.0, last.arc382, 1e-9);
		Assert.floatEquals(100.0, last.arc618, 1e-9);
	}

	public function testFibArcsResetClearsState() {
		var indicator = new FibArcs();
		for (candle in downLeg()) {
			indicator.update(candle);
		}
		indicator.reset();
		Assert.isFalse(indicator.isReady());
		Assert.isNull(indicator.update(c(100.0, 99.5, 0)));
	}

	public function testFibArcsBatchEqualsStreaming() {
		var candles = downLeg();
		var a = new FibArcs(), b = new FibArcs();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];

		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].arc382, streamed[i].arc382);
				Assert.floatEquals(batched[i].arc500, streamed[i].arc500);
				Assert.floatEquals(batched[i].arc618, streamed[i].arc618);
			}
		}
	}

	// ── FibChannel ────────────────────────────────────────────────────────────

	static function threePivots():Array<Bar> {
		return [
			c(200.0, 199.0, 0),
			c(190.0, 100.0, 1),   // confirm high @200, low candidate @100
			c(110.0, 108.0, 2),   // confirm low @100, high candidate @110
			c(220.0, 210.0, 3),   // extend high to 220 (bar 3)
			c(200.0, 150.0, 4),   // confirm high @220 -> three pivots
		];
	}

	public function testFibChannelAccessorsAndMetadata() {
		var indicator = new FibChannel();
		Assert.equals("FibChannel", indicator.name());
		Assert.equals(3, indicator.warmupPeriod());
		Assert.isFalse(indicator.isReady());
	}

	public function testFibChannelNoOutputBeforeThreePivots() {
		var indicator = new FibChannel();
		var outputs = [
			indicator.update(c(200.0, 199.0, 0)),
			indicator.update(c(190.0, 100.0, 1)),
			indicator.update(c(110.0, 108.0, 2))
		];
		for (o in outputs) Assert.isNull(o);
		Assert.isFalse(indicator.isReady());
	}

	public function testFibChannelLevelsFromThreePivots() {
		var indicator = new FibChannel();
		var last = null;
		for (candle in threePivots()) {
			last = indicator.update(candle);
		}
		Assert.notNull(last);
		Assert.isTrue(indicator.isReady());

		// Base through highs (0,200) and (3,220); width from low (1,100); cur = 4.
		var slope = (220.0 - 200.0) / 3.0;
		var baseCur = 200.0 + slope * 4.0;
		var width = 100.0 - (200.0 + slope * 1.0);

		Assert.floatEquals(baseCur, last.base, 1e-9);
		Assert.floatEquals(baseCur + width, last.level1000, 1e-9);
		Assert.floatEquals(baseCur + 0.618 * width, last.level618, 1e-9);
		Assert.floatEquals(baseCur + 1.618 * width, last.level1618, 1e-9);
	}

	public function testFibChannelResetClearsState() {
		var indicator = new FibChannel();
		for (candle in threePivots()) {
			indicator.update(candle);
		}
		Assert.isTrue(indicator.isReady());
		indicator.reset();
		Assert.isFalse(indicator.isReady());
		Assert.isNull(indicator.update(c(100.0, 99.5, 0)));
	}

	public function testFibChannelBatchEqualsStreaming() {
		var candles = threePivots();
		var a = new FibChannel(), b = new FibChannel();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];

		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].base, streamed[i].base);
				Assert.floatEquals(batched[i].level618, streamed[i].level618);
				Assert.floatEquals(batched[i].level1000, streamed[i].level1000);
				Assert.floatEquals(batched[i].level1618, streamed[i].level1618);
			}
		}
	}
}
