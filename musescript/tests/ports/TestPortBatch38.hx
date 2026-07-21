package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.PivotReversal;
import musescript.indicators.lib.SmoothedHeikinAshi;
import musescript.indicators.lib.ThreeLineBreak;
import musescript.indicators.lib.ThreeStarsInSouth;
import musescript.indicators.lib.Thrusting;
import musescript.indicators.lib.Tristar;
import musescript.indicators.lib.TrueRange;
import musescript.indicators.lib.Tweezer;
import musescript.indicators.lib.TwoCrows;
import musescript.indicators.lib.TypicalPrice;
import musescript.indicators.lib.UniqueThreeRiver;
import musescript.indicators.lib.UpsideGapThreeMethods;
import musescript.indicators.lib.UpsideGapTwoCrows;
import musescript.indicators.lib.WeightedClose;
import musescript.indicators.lib.WickRatio;
import musescript.indicators.lib.WilliamsFractals;

/**
 * Batch 38: 16 indicators ported from wickra-core (swing pivots, smoothed
 * Heikin-Ashi, line-break trend, candle patterns, per-bar transforms).
 * Known-value cases transcribed directly from the Rust fixture blocks;
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming
 * updates. (polarized_fractal_efficiency, also assigned to this batch, had
 * already landed as `pfe` in batch 22 and is covered by TestPortBatch22.)
 */
class TestPortBatch38 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, i:Int):Bar {
		return bar(price, price, price, price, 1.0, i);
	}

	// ── PivotReversal ────────────────────────────────────────────────────────

	/** Rust helper: c(high, low, close) → Candle(close, high, low, close, 1000, 0). */
	static function prBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 1000.0, i);
	}

	public function testPivotReversalRejectsZeroParams() {
		try {
			new PivotReversal(0, 2);
			Assert.fail("Should reject left == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new PivotReversal(2, 0);
			Assert.fail("Should reject right == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPivotReversalAccessorsAndMetadata() {
		var p = new PivotReversal(2, 2);
		Assert.equals(5, p.warmupPeriod());
		Assert.equals("PivotReversal", p.name());
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
		Assert.isNull(p.pivotHigh());
		Assert.isNull(p.pivotLow());
	}

	public function testPivotReversalFirstEmissionAtWarmupPeriod() {
		var p = new PivotReversal(1, 1);
		var out = IndicatorBatch.run(p, [prBar(10.0, 9.0, 9.5, 0), prBar(12.0, 11.0, 11.5, 1), prBar(10.0, 9.0, 9.5, 2)]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.notNull(out[2]);
	}

	public function testPivotReversalConfirmsPivotHighAndLow() {
		var p = new PivotReversal(1, 1);
		IndicatorBatch.run(p, [prBar(10.0, 9.0, 9.5, 0), prBar(12.0, 11.0, 11.5, 1), prBar(10.0, 9.0, 9.5, 2)]);
		Assert.floatEquals(12.0, p.pivotHigh());

		var q = new PivotReversal(1, 1);
		IndicatorBatch.run(q, [prBar(12.0, 11.0, 11.5, 0), prBar(10.0, 8.0, 8.5, 1), prBar(12.0, 11.0, 11.5, 2)]);
		Assert.floatEquals(8.0, q.pivotLow());
	}

	public function testPivotReversalBreakoutAbovePivotHighSignalsPlusOne() {
		// Form a pivot high at 12, then a close above 12 crosses it.
		var p = new PivotReversal(1, 1);
		var out = IndicatorBatch.run(p, [
			prBar(10.0, 9.0, 9.5, 0),
			prBar(12.0, 11.0, 11.5, 1), // pivot-high candidate
			prBar(10.0, 9.0, 9.5, 2),   // confirms pivot high = 12
			prBar(11.0, 9.0, 9.0, 3),   // close 9.0 (below 12)
			prBar(14.0, 12.5, 13.0, 4), // close 13.0 > 12 and prev 9.0 <= 12 -> +1
		]);
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testPivotReversalBreakdownBelowPivotLowSignalsMinusOne() {
		var p = new PivotReversal(1, 1);
		var out = IndicatorBatch.run(p, [
			prBar(12.0, 11.0, 11.5, 0),
			prBar(10.0, 8.0, 8.5, 1),   // pivot-low candidate
			prBar(12.0, 11.0, 11.5, 2), // confirms pivot low = 8
			prBar(12.0, 9.0, 11.0, 3),  // close 11 (above 8)
			prBar(9.0, 6.0, 7.0, 4),    // close 7 < 8 and prev 11 >= 8 -> -1
		]);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testPivotReversalNoBreakIsZero() {
		var p = new PivotReversal(1, 1);
		var out = IndicatorBatch.run(p, [
			prBar(10.0, 9.0, 9.5, 0),
			prBar(12.0, 11.0, 11.5, 1),
			prBar(10.0, 9.0, 9.5, 2),
			prBar(10.5, 9.0, 9.8, 3),
		]);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testPivotReversalResetClearsState() {
		var p = new PivotReversal(1, 1);
		IndicatorBatch.run(p, [prBar(10.0, 9.0, 9.5, 0), prBar(12.0, 11.0, 11.5, 1), prBar(10.0, 9.0, 9.5, 2)]);
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
		Assert.isNull(p.pivotHigh());
		Assert.isNull(p.update(prBar(10.0, 9.0, 9.5, 0)));
	}

	public function testPivotReversalBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.4) * 6.0;
			prBar(base + 1.0, base - 1.0, base, i);
		}];
		var a = new PivotReversal(2, 2);
		var b = new PivotReversal(2, 2);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── SmoothedHeikinAshi ───────────────────────────────────────────────────

	public function testSmoothedHeikinAshiRejectsZeroPeriod() {
		try {
			new SmoothedHeikinAshi(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testSmoothedHeikinAshiAccessorsAndMetadata() {
		var s = new SmoothedHeikinAshi(10);
		Assert.equals(10, s.warmupPeriod());
		Assert.equals("SmoothedHeikinAshi", s.name());
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.value());
	}

	public function testSmoothedHeikinAshiFirstEmissionAtWarmupPeriod() {
		var s = new SmoothedHeikinAshi(3);
		var bars = [for (i in 0...6) {
			var b = 100.0 + i;
			bar(b, b + 1.0, b - 1.0, b + 0.5, 1000.0, i);
		}];
		var out = IndicatorBatch.run(s, bars);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.notNull(out[2]);
	}

	public function testSmoothedHeikinAshiFirstValueSeededFromEmas() {
		// period 1: EMA(1) is the identity, so bar 1 gives
		// ha_close = (o+h+l+c)/4 and ha_open = (o+c)/2 (no prev candle).
		var s = new SmoothedHeikinAshi(1);
		var o = s.update(bar(10.0, 12.0, 8.0, 11.0, 1000.0, 0));
		Assert.notNull(o);
		Assert.floatEquals((10.0 + 12.0 + 8.0 + 11.0) / 4.0, o.close);
		Assert.floatEquals((10.0 + 11.0) / 2.0, o.open);
		Assert.floatEquals(12.0, o.high);
		Assert.floatEquals(8.0, o.low);
	}

	public function testSmoothedHeikinAshiHighBracketsOpenClose() {
		var s = new SmoothedHeikinAshi(3);
		var bars = [for (i in 0...30) {
			var b = 100.0 + i;
			bar(b, b + 2.0, b - 2.0, b + 0.5, 1000.0, i);
		}];
		for (o in IndicatorBatch.run(s, bars)) {
			if (o == null) continue;
			Assert.isTrue(o.high >= o.open && o.high >= o.close);
			Assert.isTrue(o.low <= o.open && o.low <= o.close);
		}
	}

	public function testSmoothedHeikinAshiUptrendCloseAboveOpen() {
		var s = new SmoothedHeikinAshi(3);
		var bars = [for (i in 0...30) {
			var b = 100.0 + 2.0 * i;
			bar(b, b + 1.0, b - 1.0, b + 0.5, 1000.0, i);
		}];
		var last:Null<Dynamic> = null;
		for (o in IndicatorBatch.run(s, bars)) if (o != null) last = o;
		Assert.isTrue(last.close > last.open);
	}

	public function testSmoothedHeikinAshiResetClearsState() {
		var s = new SmoothedHeikinAshi(3);
		var bars = [for (i in 0...10) {
			var b = 100.0 + i;
			bar(b, b + 1.0, b - 1.0, b, 1000.0, i);
		}];
		IndicatorBatch.run(s, bars);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.value());
		Assert.isNull(s.update(bar(100.0, 101.0, 99.0, 100.0, 1000.0, 0)));
	}

	public function testSmoothedHeikinAshiBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var b = 100.0 + Math.sin(i * 0.25) * 9.0;
			bar(b, b + 1.0, b - 1.0, b + 0.3, 1000.0, i);
		}];
		var a = new SmoothedHeikinAshi(10);
		var b2 = new SmoothedHeikinAshi(10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b2.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].open, streamed[i].open);
				Assert.floatEquals(batched[i].high, streamed[i].high);
				Assert.floatEquals(batched[i].low, streamed[i].low);
				Assert.floatEquals(batched[i].close, streamed[i].close);
			}
		}
	}

	// ── ThreeLineBreak ───────────────────────────────────────────────────────

	public function testThreeLineBreakRejectsZeroLines() {
		try {
			new ThreeLineBreak(0);
			Assert.fail("Should reject lines == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testThreeLineBreakAccessorsAndMetadata() {
		var t = new ThreeLineBreak(3);
		Assert.equals(3, t.lines());
		Assert.equals(2, t.warmupPeriod());
		Assert.equals("ThreeLineBreak", t.name());
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
	}

	public function testThreeLineBreakUptrendIsPlusOne() {
		var t = new ThreeLineBreak(3);
		var out = IndicatorBatch.run(t, [for (i in 0...20) flatBar(100.0 + i, i)]);
		Assert.isNull(out[0]);
		Assert.floatEquals(1.0, out[1]);
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testThreeLineBreakDowntrendIsMinusOne() {
		var t = new ThreeLineBreak(3);
		var out = IndicatorBatch.run(t, [for (i in 0...20) flatBar(100.0 - i, i)]);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(-1.0, last);
	}

	public function testThreeLineBreakSmallPullbackDoesNotReverse() {
		// Rise to build 3 up-lines (101, 102, 103); a dip to 102.5 stays above
		// the 3-line low (101) -> direction stays up.
		var t = new ThreeLineBreak(3);
		IndicatorBatch.run(t, [flatBar(100.0, 0), flatBar(101.0, 1), flatBar(102.0, 2), flatBar(103.0, 3)]);
		Assert.floatEquals(1.0, t.update(flatBar(102.5, 4)));
	}

	public function testThreeLineBreakBreakOfThreeLineExtremeReverses() {
		var t = new ThreeLineBreak(3);
		IndicatorBatch.run(t, [flatBar(100.0, 0), flatBar(101.0, 1), flatBar(102.0, 2), flatBar(103.0, 3)]);
		// close 100.5 breaks below the 3-line low (101) -> reverse to down.
		Assert.floatEquals(-1.0, t.update(flatBar(100.5, 4)));
	}

	public function testThreeLineBreakFlatCloseEmitsNoneUntilALineForms() {
		var t = new ThreeLineBreak(3);
		Assert.isNull(t.update(flatBar(100.0, 0)));
		// An identical close draws no line, so the direction stays unset.
		Assert.isNull(t.update(flatBar(100.0, 1)));
		Assert.isTrue(!t.isReady());
	}

	public function testThreeLineBreakResetClearsState() {
		var t = new ThreeLineBreak(3);
		IndicatorBatch.run(t, [for (i in 0...10) flatBar(100.0 + i, i)]);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
		Assert.isNull(t.update(flatBar(100.0, 0)));
	}

	public function testThreeLineBreakBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(100.0 + Math.sin(i * 0.25) * 9.0, i)];
		var a = new ThreeLineBreak(3);
		var b = new ThreeLineBreak(3);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── ThreeStarsInSouth ────────────────────────────────────────────────────

	public function testThreeStarsInSouthRejectsInvalidTolerance() {
		try {
			new ThreeStarsInSouth(-0.01);
			Assert.fail("Should reject tolerance < 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new ThreeStarsInSouth(1.0);
			Assert.fail("Should reject tolerance >= 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		// Zero tolerance is valid.
		var t = new ThreeStarsInSouth(0.0);
		Assert.floatEquals(0.0, t.tolerance());
	}

	public function testThreeStarsInSouthAccessorsAndMetadata() {
		var t = new ThreeStarsInSouth();
		Assert.equals("ThreeStarsInSouth", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.001, t.tolerance());
	}

	public function testThreeStarsInSouthIsPlusOne() {
		var t = new ThreeStarsInSouth();
		Assert.floatEquals(0.0, t.update(bar(20.0, 20.1, 8.0, 15.0, 1.0, 0)));
		Assert.floatEquals(0.0, t.update(bar(18.0, 18.1, 12.0, 16.0, 1.0, 1)));
		Assert.floatEquals(1.0, t.update(bar(15.0, 15.0, 14.0, 14.0, 1.0, 2)));
	}

	public function testThreeStarsInSouthThirdWithShadowYieldsZero() {
		var t = new ThreeStarsInSouth();
		t.update(bar(20.0, 20.1, 8.0, 15.0, 1.0, 0));
		t.update(bar(18.0, 18.1, 12.0, 16.0, 1.0, 1));
		// bar3 has a long lower shadow -> not a marubozu.
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.0, 12.5, 14.0, 1.0, 2)));
	}

	public function testThreeStarsInSouthLowerLowYieldsZero() {
		var t = new ThreeStarsInSouth();
		t.update(bar(20.0, 20.1, 8.0, 15.0, 1.0, 0));
		// bar2 dips below bar1's low -> no higher low.
		Assert.floatEquals(0.0, t.update(bar(18.0, 18.1, 7.0, 16.0, 1.0, 1)));
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.0, 14.0, 14.0, 1.0, 2)));
	}

	public function testThreeStarsInSouthResetClearsState() {
		var t = new ThreeStarsInSouth();
		t.update(bar(20.0, 20.1, 8.0, 15.0, 1.0, 0));
		t.update(bar(18.0, 18.1, 12.0, 16.0, 1.0, 1));
		t.update(bar(15.0, 15.0, 14.0, 14.0, 1.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(20.0, 20.1, 8.0, 15.0, 1.0, 0)));
	}

	public function testThreeStarsInSouthBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 2.0, base + 2.1, base - 3.0, base, 1.0, i);
		}];
		var a = new ThreeStarsInSouth();
		var b = new ThreeStarsInSouth();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── Thrusting ────────────────────────────────────────────────────────────

	public function testThrustingAccessorsAndMetadata() {
		var t = new Thrusting();
		Assert.equals("Thrusting", t.name());
		Assert.equals(2, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testThrustingIsMinusOne() {
		var t = new Thrusting();
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0)));
		Assert.floatEquals(-1.0, t.update(bar(7.0, 11.6, 6.9, 11.5, 1.0, 1)));
	}

	public function testThrustingShallowCloseYieldsZero() {
		var t = new Thrusting();
		t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0));
		// Closes barely into the body -> in-neck, not thrusting.
		Assert.floatEquals(0.0, t.update(bar(7.0, 10.3, 6.9, 10.2, 1.0, 1)));
	}

	public function testThrustingClosePastMidpointYieldsZero() {
		var t = new Thrusting();
		t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0));
		// Closes above the midpoint -> piercing, not thrusting.
		Assert.floatEquals(0.0, t.update(bar(7.0, 13.1, 6.9, 13.0, 1.0, 1)));
	}

	public function testThrustingSecondBarBlackYieldsZero() {
		var t = new Thrusting();
		t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0));
		Assert.floatEquals(0.0, t.update(bar(12.0, 12.1, 6.9, 11.5, 1.0, 1)));
	}

	public function testThrustingZeroRangeFirstBarYieldsZero() {
		var t = new Thrusting();
		t.update(bar(10.0, 10.0, 10.0, 10.0, 1.0, 0));
		Assert.floatEquals(0.0, t.update(bar(9.0, 10.0, 8.0, 9.5, 1.0, 1)));
	}

	public function testThrustingResetClearsState() {
		var t = new Thrusting();
		t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0));
		t.update(bar(7.0, 11.6, 6.9, 11.5, 1.0, 1));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.1, 9.0, 10.0, 1.0, 0)));
	}

	public function testThrustingBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 5.0, base + 5.1, base - 1.0, base, 1.0, i);
		}];
		var a = new Thrusting();
		var b = new Thrusting();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── Tristar ──────────────────────────────────────────────────────────────

	/** Rust helper: a doji centred at `mid` (tiny body, symmetric shadows). */
	static function dojiBar(mid:Float, i:Int):Bar {
		return bar(mid, mid + 1.0, mid - 1.0, mid + 0.02, 0.0, i);
	}

	/** Rust helper: a non-doji (big body). */
	static function solidBar(open:Float, close:Float, i:Int):Bar {
		return bar(open, Math.max(open, close) + 0.1, Math.min(open, close) - 0.1, close, 0.0, i);
	}

	public function testTristarAccessorsAndMetadata() {
		var t = new Tristar();
		Assert.equals(3, t.warmupPeriod());
		Assert.equals("Tristar", t.name());
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
	}

	public function testTristarFirstTwoBarsSeedWithoutSignal() {
		var t = new Tristar();
		Assert.floatEquals(0.0, t.update(dojiBar(100.0, 0)));
		Assert.floatEquals(0.0, t.update(dojiBar(100.0, 1)));
		Assert.notNull(t.update(dojiBar(100.0, 2)));
	}

	public function testTristarBearishTop() {
		// middle doji centred above the two neighbours -> top -> -1.
		var t = new Tristar();
		t.update(dojiBar(100.0, 0));
		t.update(dojiBar(105.0, 1));
		Assert.floatEquals(-1.0, t.update(dojiBar(100.0, 2)));
	}

	public function testTristarBullishBottom() {
		var t = new Tristar();
		t.update(dojiBar(100.0, 0));
		t.update(dojiBar(95.0, 1));
		Assert.floatEquals(1.0, t.update(dojiBar(100.0, 2)));
	}

	public function testTristarNonDojiIsZero() {
		var t = new Tristar();
		t.update(dojiBar(100.0, 0));
		t.update(solidBar(100.0, 110.0, 1)); // not a doji
		Assert.floatEquals(0.0, t.update(dojiBar(100.0, 2)));
	}

	public function testTristarResetClearsState() {
		var t = new Tristar();
		t.update(dojiBar(100.0, 0));
		t.update(dojiBar(105.0, 1));
		t.update(dojiBar(100.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(dojiBar(100.0, 0)));
	}

	public function testTristarBatchEqualsStreaming() {
		var bars = [for (i in 0...40) dojiBar(100.0 + Math.sin(i * 0.4) * 5.0, i)];
		var a = new Tristar();
		var b = new Tristar();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── TrueRange ────────────────────────────────────────────────────────────

	/** Rust helper: c(high, low, close) with open = midpoint(h, l). */
	static function trBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar((h + l) / 2.0, h, l, c, 1.0, i);
	}

	public function testTrueRangeReferenceValues() {
		// Bar 1 has no previous close -> TR = high - low = 12 - 8 = 4.
		// Bar 2: prev close 11, TR = max(10-9, |10-11|, |9-11|) = 2.
		var tr = new TrueRange();
		var out = IndicatorBatch.run(tr, [trBar(12.0, 8.0, 11.0, 0), trBar(10.0, 9.0, 9.5, 1)]);
		Assert.floatEquals(4.0, out[0]);
		Assert.floatEquals(2.0, out[1]);
	}

	public function testTrueRangeEmitsFromFirstCandle() {
		var tr = new TrueRange();
		Assert.equals(1, tr.warmupPeriod());
		Assert.equals("TrueRange", tr.name());
		Assert.isTrue(!tr.isReady());
		Assert.notNull(tr.update(trBar(11.0, 9.0, 10.0, 0)));
		Assert.isTrue(tr.isReady());
	}

	public function testTrueRangeNeverNegative() {
		var bars = [for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			trBar(base + 1.0, base - 1.0, base, i);
		}];
		var tr = new TrueRange();
		for (v in IndicatorBatch.run(tr, bars)) {
			if (v != null) Assert.isTrue(v >= 0.0);
		}
	}

	public function testTrueRangeResetClearsState() {
		var tr = new TrueRange();
		IndicatorBatch.run(tr, [trBar(12.0, 8.0, 10.0, 0), trBar(13.0, 9.0, 11.0, 1)]);
		Assert.isTrue(tr.isReady());
		tr.reset();
		Assert.isTrue(!tr.isReady());
		// After reset the next bar again has no previous close.
		Assert.floatEquals(4.0, tr.update(trBar(12.0, 8.0, 10.0, 0)));
	}

	public function testTrueRangeBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			trBar(mid + 1.5, mid - 1.5, mid + 0.5, i);
		}];
		var a = new TrueRange();
		var b = new TrueRange();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── Tweezer ──────────────────────────────────────────────────────────────

	public function testTweezerRejectsInvalidTolerance() {
		try {
			new Tweezer(-0.01);
			Assert.fail("Should reject tolerance < 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Tweezer(1.0);
			Assert.fail("Should reject tolerance >= 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		var t = new Tweezer(0.0);
		Assert.floatEquals(0.0, t.tolerance());
	}

	public function testTweezerAccessorsAndMetadata() {
		var t = new Tweezer();
		Assert.equals("Tweezer", t.name());
		Assert.equals(2, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.001, t.tolerance());
	}

	public function testTweezerBottomIsPlusOne() {
		var t = new Tweezer();
		Assert.floatEquals(0.0, t.update(bar(11.0, 12.0, 9.5, 9.6, 1.0, 0)));
		// Matching low 9.5.
		Assert.floatEquals(1.0, t.update(bar(9.7, 10.5, 9.5, 10.2, 1.0, 1)));
	}

	public function testTweezerTopIsMinusOne() {
		var t = new Tweezer();
		Assert.floatEquals(0.0, t.update(bar(9.0, 12.0, 8.5, 11.0, 1.0, 0)));
		// Matching high 12.0.
		Assert.floatEquals(-1.0, t.update(bar(11.5, 12.0, 11.0, 11.4, 1.0, 1)));
	}

	public function testTweezerDistinctExtremesYieldZero() {
		var t = new Tweezer();
		t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 0));
		Assert.floatEquals(0.0, t.update(bar(10.6, 11.5, 9.6, 11.2, 1.0, 1)));
	}

	public function testTweezerMatchedBothExtremesPrefersBottom() {
		// Identical candles match both highs and lows -> bottom (+1.0).
		var t = new Tweezer();
		t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 0));
		Assert.floatEquals(1.0, t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 1)));
	}

	public function testTweezerResetClearsState() {
		var t = new Tweezer();
		t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 0));
		t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 1));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(10.0, 11.0, 9.0, 10.5, 1.0, 0)));
	}

	public function testTweezerBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.1);
			bar(base, base + 2.0, base - 2.0, base + 0.5, 1.0, i);
		}];
		var a = new Tweezer();
		var b = new Tweezer();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── TwoCrows ─────────────────────────────────────────────────────────────

	public function testTwoCrowsAccessorsAndMetadata() {
		var t = new TwoCrows();
		Assert.equals("TwoCrows", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testTwoCrowsIsMinusOne() {
		// bar1 green 10->12; bar2 red 14->13 (body above bar1); bar3 red
		// opens 13.5 (inside [13,14]) and closes 11 (inside [10,12]).
		var t = new TwoCrows();
		Assert.floatEquals(0.0, t.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0)));
		Assert.floatEquals(0.0, t.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1)));
		Assert.floatEquals(-1.0, t.update(bar(13.5, 13.6, 10.9, 11.0, 1.0, 2)));
	}

	public function testTwoCrowsNoGapUpYieldsZero() {
		var t = new TwoCrows();
		t.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		t.update(bar(11.5, 12.0, 10.4, 11.0, 1.0, 1));
		Assert.floatEquals(0.0, t.update(bar(11.0, 11.2, 9.9, 10.5, 1.0, 2)));
	}

	public function testTwoCrowsThirdCloseBelowFirstBodyYieldsZero() {
		var t = new TwoCrows();
		t.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		t.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1));
		// bar3 closes 9.5, below bar1's body low (10) -> not Two Crows.
		Assert.floatEquals(0.0, t.update(bar(13.5, 13.6, 9.4, 9.5, 1.0, 2)));
	}

	public function testTwoCrowsResetClearsState() {
		var t = new TwoCrows();
		t.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		t.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1));
		t.update(bar(13.5, 13.6, 10.9, 11.0, 1.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0)));
	}

	public function testTwoCrowsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			if (i % 3 == 0) bar(base, base + 0.5, base - 1.0, base + 0.4, 1.0, i);
			else bar(base + 1.5, base + 1.7, base - 0.2, base + 0.6, 1.0, i);
		}];
		var a = new TwoCrows();
		var b = new TwoCrows();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── TypicalPrice ─────────────────────────────────────────────────────────

	public function testTypicalPriceReferenceValue() {
		// (high + low + close) / 3 = (12 + 6 + 9) / 3 = 9.
		var tp = new TypicalPrice();
		Assert.floatEquals(9.0, tp.update(bar(9.0, 12.0, 6.0, 9.0, 1.0, 0)));
	}

	public function testTypicalPriceEmitsFromFirstCandle() {
		var tp = new TypicalPrice();
		Assert.equals(1, tp.warmupPeriod());
		Assert.equals("TypicalPrice", tp.name());
		Assert.isTrue(!tp.isReady());
		Assert.notNull(tp.update(bar(10.0, 11.0, 9.0, 10.0, 1.0, 0)));
		Assert.isTrue(tp.isReady());
	}

	public function testTypicalPriceResetClearsState() {
		var tp = new TypicalPrice();
		tp.update(bar(10.0, 11.0, 9.0, 10.0, 1.0, 0));
		Assert.isTrue(tp.isReady());
		tp.reset();
		Assert.isTrue(!tp.isReady());
	}

	public function testTypicalPriceBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 2.0, base + 1.0, 1.0, i);
		}];
		var a = new TypicalPrice();
		var b = new TypicalPrice();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── UniqueThreeRiver ─────────────────────────────────────────────────────

	public function testUniqueThreeRiverAccessorsAndMetadata() {
		var t = new UniqueThreeRiver();
		Assert.equals("UniqueThreeRiver", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testUniqueThreeRiverIsPlusOne() {
		var t = new UniqueThreeRiver();
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.1, 10.0, 10.5, 1.0, 0)));
		Assert.floatEquals(0.0, t.update(bar(14.0, 14.1, 9.0, 11.0, 1.0, 1)));
		Assert.floatEquals(1.0, t.update(bar(10.2, 10.9, 9.5, 10.4, 1.0, 2)));
	}

	public function testUniqueThreeRiverFirstBarNotBlackYieldsZero() {
		var t = new UniqueThreeRiver();
		// bar1 white.
		t.update(bar(10.5, 15.1, 10.0, 15.0, 1.0, 0));
		t.update(bar(14.0, 14.1, 9.0, 11.0, 1.0, 1));
		Assert.floatEquals(0.0, t.update(bar(10.2, 10.9, 9.5, 10.4, 1.0, 2)));
	}

	public function testUniqueThreeRiverSecondBarNoNewLowYieldsZero() {
		var t = new UniqueThreeRiver();
		t.update(bar(15.0, 15.1, 10.0, 10.5, 1.0, 0));
		// bar2 black, inside, but does not make a new low.
		t.update(bar(14.0, 14.1, 10.5, 11.0, 1.0, 1));
		Assert.floatEquals(0.0, t.update(bar(10.2, 10.9, 9.5, 10.4, 1.0, 2)));
	}

	public function testUniqueThreeRiverThirdBarLargeBodyYieldsZero() {
		var t = new UniqueThreeRiver();
		t.update(bar(15.0, 15.1, 10.0, 10.5, 1.0, 0));
		t.update(bar(14.0, 14.1, 9.0, 11.0, 1.0, 1));
		// bar3 white but with a large body.
		Assert.floatEquals(0.0, t.update(bar(9.6, 10.9, 9.5, 10.8, 1.0, 2)));
	}

	public function testUniqueThreeRiverResetClearsState() {
		var t = new UniqueThreeRiver();
		t.update(bar(15.0, 15.1, 10.0, 10.5, 1.0, 0));
		t.update(bar(14.0, 14.1, 9.0, 11.0, 1.0, 1));
		t.update(bar(10.2, 10.9, 9.5, 10.4, 1.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(15.0, 15.1, 10.0, 10.5, 1.0, 0)));
	}

	public function testUniqueThreeRiverBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 200.0 - i;
			bar(base, base + 0.1, base - 5.2, base - 5.0, 1.0, i);
		}];
		var a = new UniqueThreeRiver();
		var b = new UniqueThreeRiver();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── UpsideGapThreeMethods ────────────────────────────────────────────────

	public function testUpsideGapThreeMethodsAccessorsAndMetadata() {
		var t = new UpsideGapThreeMethods();
		Assert.equals("UpsideGapThreeMethods", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testUpsideGapThreeMethodsIsPlusOne() {
		var t = new UpsideGapThreeMethods();
		Assert.floatEquals(0.0, t.update(bar(10.0, 11.2, 9.8, 11.0, 1.0, 0)));
		Assert.floatEquals(0.0, t.update(bar(12.0, 13.2, 11.9, 13.0, 1.0, 1)));
		Assert.floatEquals(1.0, t.update(bar(12.5, 12.6, 10.4, 10.5, 1.0, 2)));
	}

	public function testUpsideGapThreeMethodsNoGapYieldsZero() {
		var t = new UpsideGapThreeMethods();
		t.update(bar(10.0, 13.2, 9.8, 13.0, 1.0, 0));
		// bar2 opens below bar1's close -> no upside body gap.
		t.update(bar(11.0, 13.2, 10.9, 12.5, 1.0, 1));
		Assert.floatEquals(0.0, t.update(bar(12.0, 12.6, 10.4, 10.5, 1.0, 2)));
	}

	public function testUpsideGapThreeMethodsThirdBarNotBlackYieldsZero() {
		var t = new UpsideGapThreeMethods();
		t.update(bar(10.0, 11.2, 9.8, 11.0, 1.0, 0));
		t.update(bar(12.0, 13.2, 11.9, 13.0, 1.0, 1));
		// bar3 white.
		Assert.floatEquals(0.0, t.update(bar(10.5, 12.6, 10.4, 12.5, 1.0, 2)));
	}

	public function testUpsideGapThreeMethodsResetClearsState() {
		var t = new UpsideGapThreeMethods();
		t.update(bar(10.0, 11.2, 9.8, 11.0, 1.0, 0));
		t.update(bar(12.0, 13.2, 11.9, 13.0, 1.0, 1));
		t.update(bar(12.5, 12.6, 10.4, 10.5, 1.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(10.0, 11.2, 9.8, 11.0, 1.0, 0)));
	}

	public function testUpsideGapThreeMethodsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 5.2, base - 0.1, base + 5.0, 1.0, i);
		}];
		var a = new UpsideGapThreeMethods();
		var b = new UpsideGapThreeMethods();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── UpsideGapTwoCrows ────────────────────────────────────────────────────

	public function testUpsideGapTwoCrowsAccessorsAndMetadata() {
		var u = new UpsideGapTwoCrows();
		Assert.equals("UpsideGapTwoCrows", u.name());
		Assert.equals(3, u.warmupPeriod());
		Assert.isTrue(!u.isReady());
	}

	public function testUpsideGapTwoCrowsIsMinusOne() {
		// bar1 green 10->12; bar2 red 14->13 gapping up; bar3 red opens 15
		// (above bar2 open) and closes 12.5 (below bar2 close, above bar1 close).
		var u = new UpsideGapTwoCrows();
		Assert.floatEquals(0.0, u.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0)));
		Assert.floatEquals(0.0, u.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1)));
		Assert.floatEquals(-1.0, u.update(bar(15.0, 15.2, 12.4, 12.5, 1.0, 2)));
	}

	public function testUpsideGapTwoCrowsClosingTheFirstGapYieldsZero() {
		var u = new UpsideGapTwoCrows();
		u.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		u.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1));
		// bar3 closes 11.5, below bar1's close (12) -> gap closed, not the pattern.
		Assert.floatEquals(0.0, u.update(bar(15.0, 15.2, 11.4, 11.5, 1.0, 2)));
	}

	public function testUpsideGapTwoCrowsNoGapUpYieldsZero() {
		var u = new UpsideGapTwoCrows();
		u.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		// bar2's body does not gap above bar1's body.
		u.update(bar(11.5, 12.0, 10.4, 11.0, 1.0, 1));
		Assert.floatEquals(0.0, u.update(bar(12.0, 12.2, 10.9, 11.5, 1.0, 2)));
	}

	public function testUpsideGapTwoCrowsResetClearsState() {
		var u = new UpsideGapTwoCrows();
		u.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0));
		u.update(bar(14.0, 14.2, 12.9, 13.0, 1.0, 1));
		u.update(bar(15.0, 15.2, 12.4, 12.5, 1.0, 2));
		Assert.isTrue(u.isReady());
		u.reset();
		Assert.isTrue(!u.isReady());
		Assert.floatEquals(0.0, u.update(bar(10.0, 12.2, 9.9, 12.0, 1.0, 0)));
	}

	public function testUpsideGapTwoCrowsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			if (i % 3 == 0) bar(base, base + 0.5, base - 1.0, base + 0.4, 1.0, i);
			else bar(base + 1.5, base + 1.7, base - 0.2, base + 0.6, 1.0, i);
		}];
		var a = new UpsideGapTwoCrows();
		var b = new UpsideGapTwoCrows();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── WeightedClose ────────────────────────────────────────────────────────

	public function testWeightedCloseReferenceValue() {
		// (high + low + 2·close) / 4 = (12 + 8 + 22) / 4 = 10.5.
		var wc = new WeightedClose();
		Assert.floatEquals(10.5, wc.update(bar(10.0, 12.0, 8.0, 11.0, 1.0, 0)));
	}

	public function testWeightedCloseEmitsFromFirstCandle() {
		var wc = new WeightedClose();
		Assert.equals(1, wc.warmupPeriod());
		Assert.equals("WeightedClose", wc.name());
		Assert.isTrue(!wc.isReady());
		Assert.notNull(wc.update(bar(10.0, 11.0, 9.0, 10.0, 1.0, 0)));
		Assert.isTrue(wc.isReady());
	}

	public function testWeightedCloseResetClearsState() {
		var wc = new WeightedClose();
		wc.update(bar(10.0, 11.0, 9.0, 10.0, 1.0, 0));
		Assert.isTrue(wc.isReady());
		wc.reset();
		Assert.isTrue(!wc.isReady());
	}

	public function testWeightedCloseBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 2.0, base + 1.0, 1.0, i);
		}];
		var a = new WeightedClose();
		var b = new WeightedClose();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── WickRatio ────────────────────────────────────────────────────────────

	public function testWickRatioUpperShadowDominatesIsPositive() {
		// upper 13 - 10.5 = 2.5, lower 10 - 10 = 0, range 3 -> +2.5/3.
		var wr = new WickRatio();
		Assert.floatEquals(2.5 / 3.0, wr.update(bar(10.0, 13.0, 10.0, 10.5, 1.0, 0)));
	}

	public function testWickRatioLowerShadowDominatesIsNegative() {
		// Hammer: open 12, close 12.5, high 13, low 9: upper 0.5, lower 3, range 4.
		var wr = new WickRatio();
		Assert.floatEquals((0.5 - 3.0) / 4.0, wr.update(bar(12.0, 13.0, 9.0, 12.5, 1.0, 0)));
	}

	public function testWickRatioSymmetricWicksAreZero() {
		var wr = new WickRatio();
		Assert.floatEquals(0.0, wr.update(bar(10.0, 12.0, 8.0, 10.0, 1.0, 0)));
	}

	public function testWickRatioZeroRangeBarYieldsZero() {
		var wr = new WickRatio();
		Assert.floatEquals(0.0, wr.update(bar(10.0, 10.0, 10.0, 10.0, 1.0, 0)));
	}

	public function testWickRatioStaysWithinUnitRange() {
		var bars = [for (i in 0...100) {
			var mid = 100.0 + Math.sin(i * 0.2) * 8.0;
			var close = mid + Math.cos(i * 0.5) * 2.0;
			bar(mid, mid + 3.0, mid - 3.0, close, 1.0, i);
		}];
		var wr = new WickRatio();
		for (v in IndicatorBatch.run(wr, bars)) {
			if (v != null) Assert.isTrue(v >= -1.0 && v <= 1.0);
		}
	}

	public function testWickRatioEmitsFromFirstCandleAndResets() {
		var wr = new WickRatio();
		Assert.equals(1, wr.warmupPeriod());
		Assert.equals("WickRatio", wr.name());
		Assert.isTrue(!wr.isReady());
		Assert.notNull(wr.update(bar(10.0, 11.0, 9.0, 10.0, 1.0, 0)));
		Assert.isTrue(wr.isReady());
		wr.reset();
		Assert.isTrue(!wr.isReady());
	}

	public function testWickRatioBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 2.0, base + 1.0, 1.0, i);
		}];
		var a = new WickRatio();
		var b = new WickRatio();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── WilliamsFractals ─────────────────────────────────────────────────────

	/** Rust helper: c(h, l) → Candle(l, h, l, l, 1, ts). */
	static function wfBar(h:Float, l:Float, i:Int):Bar {
		return bar(l, h, l, l, 1.0, i);
	}

	public function testWilliamsFractalsIsolatedPeakIsUpFractal() {
		var wf = new WilliamsFractals();
		// Highs 1, 2, 5, 2, 1 -> centre (5) is strictly above its four neighbours.
		var highs = [1.0, 2.0, 5.0, 2.0, 1.0];
		var last = null;
		for (i in 0...highs.length) last = wf.update(wfBar(highs[i], highs[i] - 0.5, i));
		Assert.notNull(last);
		Assert.floatEquals(5.0, last.up);
		Assert.isNull(last.down);
	}

	public function testWilliamsFractalsIsolatedTroughIsDownFractal() {
		var wf = new WilliamsFractals();
		// Lows 5, 4, 1, 4, 5 -> centre is the trough.
		var lows = [5.0, 4.0, 1.0, 4.0, 5.0];
		var last = null;
		for (i in 0...lows.length) last = wf.update(wfBar(lows[i] + 0.5, lows[i], i));
		Assert.notNull(last);
		Assert.floatEquals(1.0, last.down);
		Assert.isNull(last.up);
	}

	public function testWilliamsFractalsMonotonicSeriesYieldsNoFractals() {
		var wf = new WilliamsFractals();
		var emitted = 0;
		for (i in 0...10) {
			var o = wf.update(wfBar(i + 2.0, i + 0.0, i));
			if (o != null) {
				emitted++;
				Assert.isNull(o.up);
				Assert.isNull(o.down);
			}
		}
		Assert.isTrue(emitted >= 6);
	}

	public function testWilliamsFractalsEqualNeighbourIsNotAFractal() {
		// Centre tied with neighbour -> strict inequality fails -> no fractal.
		var wf = new WilliamsFractals();
		var highs = [1.0, 5.0, 5.0, 2.0, 1.0];
		var last = null;
		for (i in 0...highs.length) last = wf.update(wfBar(highs[i], highs[i] - 0.5, i));
		Assert.isNull(last.up);
	}

	public function testWilliamsFractalsFirstFourBarsReturnNull() {
		var wf = new WilliamsFractals();
		Assert.equals(5, wf.warmupPeriod());
		Assert.equals("WilliamsFractals", wf.name());
		for (i in 0...4) Assert.isNull(wf.update(wfBar(10.0, 9.0, i)));
		Assert.isTrue(!wf.isReady());
	}

	public function testWilliamsFractalsResetClearsState() {
		var wf = new WilliamsFractals();
		for (i in 0...5) wf.update(wfBar(10.0, 9.0, i));
		Assert.isTrue(wf.isReady());
		wf.reset();
		Assert.isTrue(!wf.isReady());
		Assert.isNull(wf.update(wfBar(10.0, 9.0, 0)));
	}

	public function testWilliamsFractalsBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var mid = 100.0 + Math.sin(i * 0.4) * 6.0;
			wfBar(mid + 2.0, mid, i);
		}];
		var a = new WilliamsFractals();
		var b = new WilliamsFractals();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.equals(batched[i].up == null, streamed[i].up == null);
				if (batched[i].up != null) Assert.floatEquals(batched[i].up, streamed[i].up);
				Assert.equals(batched[i].down == null, streamed[i].down == null);
				if (batched[i].down != null) Assert.floatEquals(batched[i].down, streamed[i].down);
			}
		}
	}
}
