package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.AutoFib;
import musescript.indicators.lib.Bat;
import musescript.indicators.lib.Butterfly;
import musescript.indicators.lib.Crab;
import musescript.indicators.lib.CupAndHandle;
import musescript.indicators.lib.Cypher;
import musescript.indicators.lib.HeadAndShoulders;
import musescript.indicators.lib.RectangleRange;
import musescript.indicators.lib.Shark;
import musescript.indicators.lib.ThreeDrives;
import musescript.indicators.lib.TowerTopBottom;
import musescript.indicators.lib.Triangle;
import musescript.indicators.lib.TripleTopBottom;
import musescript.indicators.lib.Wedge;
import musescript.indicators.lib.ZigZag;

/**
 * Batch 36: 15 harmonic & chart pattern indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch36 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Helper: candles_for_pivots (mirrors Rust pattern_swing::candles_for_pivots) ──

	static function candlesForPivots(pivots:Array<Float>):Array<Bar> {
		var out:Array<Bar> = [];
		out.push(bar(pivots[0], pivots[0], pivots[0] * 0.999, pivots[0] * 0.999, 1.0, 0));

		var ts = 0;
		for (k in 0...pivots.length) {
			ts++;
			var price = pivots[k];
			var isHigh = k % 2 == 0;
			var next = if (k + 1 < pivots.length) {
				pivots[k + 1];
			} else {
				isHigh ? price * 0.90 : price * 1.10;
			};

			var b = if (isHigh) {
				// Reverse down from candidate high
				bar(price * 0.99, price * 0.99, next, next, 1.0, ts);
			} else {
				// Reverse up from candidate low
				bar(next, next, price * 1.01, price * 1.01, 1.0, ts);
			};
			out.push(b);
		}
		return out;
	}

	/** Snapshot harmonic `.signal` (update reuses one out object). */
	static function harmonicSignals(ind:Dynamic, bars:Array<Bar>):Array<Null<Float>> {
		return [for (x in bars) {
			var o = ind.update(x);
			o == null ? null : o.signal;
		}];
	}

	static function assertBatchEqualsStreamingHarmonic(a:Dynamic, b:Dynamic, bars:Array<Bar>):Void {
		var batched = harmonicSignals(a, bars);
		var streamed = harmonicSignals(b, bars);
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	static function assertBatchEqualsStreamingScalar(a:MuseIndicatorBar, b:MuseIndicatorBar, bars:Array<Bar>):Void {
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── AutoFib ──────────────────────────────────────────────────────────────

	public function testAutoFibAccessorsAndMetadata() {
		var a = new AutoFib();
		Assert.equals("AutoFib", a.name());
		Assert.equals(2, a.warmupPeriod());
		Assert.isTrue(!a.isReady());
	}

	public function testAutoFibNoOutputBeforeTwoPivots() {
		var a = new AutoFib();
		var outputs = [for (c in candlesForPivots([120.0])) a.update(c)];
		for (v in outputs) {
			Assert.isNull(v);
		}
	}

	public function testAutoFibAnchorsOnTheLargestLeg() {
		// Pivots: 130 -> 120 (small, 10) -> 220 (large, 100) -> 200 (small, 20).
		// The dominant leg is 120 -> 220; its retracement spans [120, 220].
		var a = new AutoFib();
		var last:Null<AutoFibOutput> = null;
		for (c in candlesForPivots([130.0, 120.0, 220.0, 200.0])) {
			last = a.update(c);
		}
		Assert.isTrue(a.isReady());
		Assert.notNull(last);
		// Largest leg 120 -> 220: 0% on 220 (end), 100% on 120 (start).
		Assert.floatEquals(220.0, last.level0);
		Assert.floatEquals(120.0, last.level1000);
		Assert.floatEquals(170.0, last.level500);
		Assert.floatEquals(220.0 + 0.618 * (120.0 - 220.0), last.level618);
	}

	public function testAutoFibResetClearsState() {
		var a = new AutoFib();
		for (c in candlesForPivots([200.0, 100.0])) {
			a.update(c);
		}
		Assert.isTrue(a.isReady());
		a.reset();
		Assert.isTrue(!a.isReady());
		Assert.isNull(a.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testAutoFibBatchEqualsStreaming() {
		var bars = candlesForPivots([130.0, 120.0, 220.0, 200.0]);
		var a = new AutoFib();
		var b = new AutoFib();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].level0, streamed[i].level0);
				Assert.floatEquals(batched[i].level236, streamed[i].level236);
				Assert.floatEquals(batched[i].level382, streamed[i].level382);
				Assert.floatEquals(batched[i].level500, streamed[i].level500);
				Assert.floatEquals(batched[i].level618, streamed[i].level618);
				Assert.floatEquals(batched[i].level786, streamed[i].level786);
				Assert.floatEquals(batched[i].level1000, streamed[i].level1000);
			}
		}
	}

	// ── Bat ──────────────────────────────────────────────────────────────────

	public function testBatAccessorsAndMetadata() {
		var b = new Bat();
		Assert.equals("Bat", b.name());
		Assert.equals(6, b.warmupPeriod());
		Assert.isTrue(!b.isReady());
	}

	public function testBatBullishIsPlusOne() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 122.0, 137.0, 104.56]);
		var out = harmonicSignals(new Bat(), bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testBatBearishIsMinusOne() {
		var bars = candlesForPivots([150.0, 110.0, 128.0, 113.0, 145.44]);
		var out = harmonicSignals(new Bat(), bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testBatOutOfRatioDoesNotTrigger() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0]);
		var out = harmonicSignals(new Bat(), bars);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testBatResetClearsState() {
		var b = new Bat();
		for (c in candlesForPivots([150.0, 100.0, 140.0])) {
			b.update(c);
		}
		b.reset();
		Assert.isTrue(!b.isReady());
		Assert.floatEquals(0.0, b.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)).signal);
	}

	public function testBatBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 122.0, 137.0, 104.56]);
		assertBatchEqualsStreamingHarmonic(new Bat(), new Bat(), bars);
	}

	// ── Butterfly ────────────────────────────────────────────────────────────

	public function testButterflyAccessorsAndMetadata() {
		var b = new Butterfly();
		Assert.equals("Butterfly", b.name());
		Assert.equals(6, b.warmupPeriod());
		Assert.isTrue(!b.isReady());
	}

	public function testButterflyBullishIsPlusOne() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 108.6, 128.0, 79.8]);
		var out = harmonicSignals(new Butterfly(), bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testButterflyBearishIsMinusOne() {
		var bars = candlesForPivots([150.0, 110.0, 141.4, 121.4, 170.2]);
		var out = harmonicSignals(new Butterfly(), bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testButterflyOutOfRatioDoesNotTrigger() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0]);
		var out = harmonicSignals(new Butterfly(), bars);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testButterflyResetClearsState() {
		var b = new Butterfly();
		for (c in candlesForPivots([150.0, 100.0, 140.0])) {
			b.update(c);
		}
		b.reset();
		Assert.isTrue(!b.isReady());
		Assert.floatEquals(0.0, b.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)).signal);
	}

	public function testButterflyBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 108.6, 128.0, 79.8]);
		assertBatchEqualsStreamingHarmonic(new Butterfly(), new Butterfly(), bars);
	}

	// ── Crab ─────────────────────────────────────────────────────────────────

	public function testCrabAccessorsAndMetadata() {
		var c = new Crab();
		Assert.equals("Crab", c.name());
		Assert.equals(6, c.warmupPeriod());
		Assert.isTrue(!c.isReady());
	}

	public function testCrabBullishIsPlusOne() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 120.0, 137.5, 75.3]);
		var out = harmonicSignals(new Crab(), bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testCrabBearishIsMinusOne() {
		var bars = candlesForPivots([150.0, 110.0, 130.0, 112.5, 174.7]);
		var out = harmonicSignals(new Crab(), bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testCrabOutOfRatioDoesNotTrigger() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0]);
		var out = harmonicSignals(new Crab(), bars);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testCrabResetClearsState() {
		var c = new Crab();
		for (x in candlesForPivots([150.0, 100.0, 140.0])) {
			c.update(x);
		}
		c.reset();
		Assert.isTrue(!c.isReady());
		Assert.floatEquals(0.0, c.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)).signal);
	}

	public function testCrabBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 120.0, 137.5, 75.3]);
		assertBatchEqualsStreamingHarmonic(new Crab(), new Crab(), bars);
	}

	// ── Cypher ───────────────────────────────────────────────────────────────

	public function testCypherAccessorsAndMetadata() {
		var c = new Cypher();
		Assert.equals("Cypher", c.name());
		Assert.equals(6, c.warmupPeriod());
		Assert.isTrue(!c.isReady());
	}

	public function testCypherBullishIsPlusOne() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 120.0, 168.0, 114.55]);
		var out = harmonicSignals(new Cypher(), bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testCypherBearishIsMinusOne() {
		var bars = candlesForPivots([150.0, 110.0, 130.0, 82.0, 135.45]);
		var out = harmonicSignals(new Cypher(), bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testCypherOutOfRatioDoesNotTrigger() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0]);
		var out = harmonicSignals(new Cypher(), bars);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testCypherResetClearsState() {
		var c = new Cypher();
		for (x in candlesForPivots([150.0, 100.0, 140.0])) {
			c.update(x);
		}
		c.reset();
		Assert.isTrue(!c.isReady());
		Assert.floatEquals(0.0, c.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)).signal);
	}

	public function testCypherBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 120.0, 168.0, 114.55]);
		assertBatchEqualsStreamingHarmonic(new Cypher(), new Cypher(), bars);
	}

	// ── Shark ────────────────────────────────────────────────────────────────

	public function testSharkAccessorsAndMetadata() {
		var s = new Shark();
		Assert.equals("Shark", s.name());
		Assert.equals(6, s.warmupPeriod());
		Assert.isTrue(!s.isReady());
	}

	public function testSharkBullishIsPlusOne() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 88.0, 186.8, 100.0]);
		var out = harmonicSignals(new Shark(), bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testSharkBearishIsMinusOne() {
		var bars = candlesForPivots([150.0, 110.0, 162.0, 60.2, 150.0]);
		var out = harmonicSignals(new Shark(), bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testSharkOutOfRatioDoesNotTrigger() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0]);
		var out = harmonicSignals(new Shark(), bars);
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testSharkResetClearsState() {
		var s = new Shark();
		for (x in candlesForPivots([150.0, 100.0, 140.0])) {
			s.update(x);
		}
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.floatEquals(0.0, s.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)).signal);
	}

	public function testSharkBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 88.0, 186.8, 100.0]);
		assertBatchEqualsStreamingHarmonic(new Shark(), new Shark(), bars);
	}

	// ── ThreeDrives ──────────────────────────────────────────────────────────

	public function testThreeDrivesAccessorsAndMetadata() {
		var t = new ThreeDrives();
		Assert.equals("ThreeDrives", t.name());
		Assert.equals(6, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testThreeDrivesBearishIsMinusOne() {
		// Three rising drives (120, 128, 136) → bearish exhaustion.
		var t = new ThreeDrives();
		var out = [for (x in candlesForPivots([120.0, 100.0, 128.0, 108.0, 136.0])) t.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testThreeDrivesBullishIsPlusOne() {
		// Three falling drives → bullish exhaustion.
		var t = new ThreeDrives();
		var out = [for (x in candlesForPivots([150.0, 120.0, 140.0, 112.0, 132.0, 104.0])) t.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testThreeDrivesAsymmetricDoesNotTrigger() {
		var t = new ThreeDrives();
		var out = [for (x in candlesForPivots([150.0, 100.0, 140.0, 110.0, 135.0, 105.0])) t.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testThreeDrivesResetClearsState() {
		var t = new ThreeDrives();
		for (x in candlesForPivots([120.0, 100.0, 128.0])) {
			t.update(x);
		}
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testThreeDrivesBatchEqualsStreaming() {
		var bars = candlesForPivots([120.0, 100.0, 128.0, 108.0, 136.0]);
		assertBatchEqualsStreamingScalar(new ThreeDrives(), new ThreeDrives(), bars);
	}

	// ── HeadAndShoulders ─────────────────────────────────────────────────────

	public function testHeadAndShouldersAccessorsAndMetadata() {
		var h = new HeadAndShoulders();
		Assert.equals("HeadAndShoulders", h.name());
		Assert.equals(6, h.warmupPeriod());
		Assert.isTrue(!h.isReady());
	}

	public function testHeadAndShouldersTopIsMinusOne() {
		// LS 100, trough 90, head 120, trough 92, RS 101.
		var h = new HeadAndShoulders();
		var out = [for (x in candlesForPivots([100.0, 90.0, 120.0, 92.0, 101.0])) h.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testInverseHeadAndShouldersIsPlusOne() {
		// Lead high then LS 100, peak 110, head 80, peak 108, RS 101.
		var h = new HeadAndShoulders();
		var out = [for (x in candlesForPivots([130.0, 100.0, 110.0, 80.0, 108.0, 101.0])) h.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testHeadAndShouldersMismatchedShouldersDoNotTrigger() {
		// Right shoulder (115) far from left (100) → no pattern.
		var h = new HeadAndShoulders();
		var out = [for (x in candlesForPivots([100.0, 90.0, 130.0, 92.0, 115.0])) h.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testInverseMismatchedShouldersDoNotTrigger() {
		// Inverse shape (ends on a low) but the right shoulder (90) diverges from
		// the left (100) → enters the inverse branch yet reports no pattern.
		var h = new HeadAndShoulders();
		var out = [for (x in candlesForPivots([130.0, 100.0, 110.0, 80.0, 108.0, 90.0])) h.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testEqualHighsWithoutTallerHeadDoNotTrigger() {
		// Three equal highs (no dominant head) → not H&S (that is a triple top).
		var h = new HeadAndShoulders();
		var out = [for (x in candlesForPivots([120.0, 90.0, 120.0, 92.0, 120.0])) h.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testHeadAndShouldersResetClearsState() {
		var h = new HeadAndShoulders();
		for (x in candlesForPivots([100.0, 90.0, 120.0])) {
			h.update(x);
		}
		h.reset();
		Assert.isTrue(!h.isReady());
		Assert.floatEquals(0.0, h.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testHeadAndShouldersBatchEqualsStreaming() {
		var bars = candlesForPivots([100.0, 90.0, 120.0, 92.0, 101.0]);
		assertBatchEqualsStreamingScalar(new HeadAndShoulders(), new HeadAndShoulders(), bars);
	}

	// ── CupAndHandle ─────────────────────────────────────────────────────────

	public function testCupAndHandleAccessorsAndMetadata() {
		var c = new CupAndHandle();
		Assert.equals("CupAndHandle", c.name());
		Assert.equals(5, c.warmupPeriod());
		Assert.isTrue(!c.isReady());
	}

	public function testCupAndHandleIsPlusOne() {
		// Rims 120/121, cup 90 (deep), handle 110 (shallow, above the cup).
		var c = new CupAndHandle();
		var out = [for (x in candlesForPivots([120.0, 90.0, 121.0, 110.0])) c.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testInverseCupAndHandleIsMinusOne() {
		// Lead high then rims 100/101, cap 130, handle 110 (below cap, above rim).
		var c = new CupAndHandle();
		var out = [for (x in candlesForPivots([140.0, 100.0, 130.0, 101.0, 110.0])) c.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testDeepHandleIsNotCupAndHandle() {
		// Handle (85) below the cup low (90) → a double bottom, not cup-and-handle.
		var c = new CupAndHandle();
		var out = [for (x in candlesForPivots([120.0, 90.0, 121.0, 85.0])) c.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testInverseWithMismatchedRimsDoesNotTrigger() {
		// Inverse shape (ends high) but the rims (100 / 90) diverge → enters the
		// inverse branch yet reports no pattern.
		var c = new CupAndHandle();
		var out = [for (x in candlesForPivots([140.0, 100.0, 130.0, 90.0, 110.0])) c.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testCupAndHandleResetClearsState() {
		var c = new CupAndHandle();
		for (x in candlesForPivots([120.0, 90.0, 121.0])) {
			c.update(x);
		}
		c.reset();
		Assert.isTrue(!c.isReady());
		Assert.floatEquals(0.0, c.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testCupAndHandleBatchEqualsStreaming() {
		var bars = candlesForPivots([120.0, 90.0, 121.0, 110.0]);
		assertBatchEqualsStreamingScalar(new CupAndHandle(), new CupAndHandle(), bars);
	}

	// ── Triangle ─────────────────────────────────────────────────────────────

	public function testTriangleAccessorsAndMetadata() {
		var t = new Triangle();
		Assert.equals("Triangle", t.name());
		Assert.equals(5, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testAscendingTriangleIsPlusOne() {
		// Flat highs (120, 120), rising lows (100 → 110).
		var t = new Triangle();
		var out = [for (x in candlesForPivots([130.0, 100.0, 120.0, 110.0, 120.0])) t.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testDescendingTriangleIsMinusOne() {
		// Falling highs (120 → 110), flat lows (100, 99).
		var t = new Triangle();
		var out = [for (x in candlesForPivots([120.0, 100.0, 110.0, 99.0])) t.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testSymmetricalTriangleEndingLowIsPlusOne() {
		// Falling highs (120 → 113), rising lows (100 → 106); last pivot a low.
		var t = new Triangle();
		var out = [for (x in candlesForPivots([120.0, 100.0, 113.0, 106.0])) t.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testSymmetricalTriangleEndingHighIsMinusOne() {
		// Same convergence but ending on a high pivot.
		var t = new Triangle();
		var out = [for (x in candlesForPivots([130.0, 100.0, 120.0, 106.0, 113.0])) t.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testExpandingSwingsAreNotATriangle() {
		// Rising highs and falling lows (broadening) → no converging triangle.
		var t = new Triangle();
		var out = [for (x in candlesForPivots([110.0, 100.0, 130.0, 80.0])) t.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testTriangleResetClearsState() {
		var t = new Triangle();
		for (x in candlesForPivots([130.0, 100.0, 120.0])) {
			t.update(x);
		}
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testTriangleBatchEqualsStreaming() {
		var bars = candlesForPivots([130.0, 100.0, 120.0, 110.0, 120.0]);
		assertBatchEqualsStreamingScalar(new Triangle(), new Triangle(), bars);
	}

	// ── Wedge ────────────────────────────────────────────────────────────────

	public function testWedgeAccessorsAndMetadata() {
		var w = new Wedge();
		Assert.equals("Wedge", w.name());
		Assert.equals(5, w.warmupPeriod());
		Assert.isTrue(!w.isReady());
	}

	public function testRisingWedgeIsMinusOne() {
		// Highs 100 → 103 (+3), lows 90 → 94 (+4, steeper) → rising wedge.
		var w = new Wedge();
		var out = [for (x in candlesForPivots([110.0, 90.0, 100.0, 94.0, 103.0])) w.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testFallingWedgeIsPlusOne() {
		// Highs 120 → 106 (-14, steeper), lows 100 → 99 (-1) → falling wedge.
		var w = new Wedge();
		var out = [for (x in candlesForPivots([120.0, 100.0, 106.0, 99.0])) w.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testDivergingSwingsAreNotAWedge() {
		// Rising highs but falling lows (broadening) → no wedge.
		var w = new Wedge();
		var out = [for (x in candlesForPivots([110.0, 100.0, 130.0, 80.0])) w.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testWedgeResetClearsState() {
		var w = new Wedge();
		for (x in candlesForPivots([110.0, 90.0, 100.0])) {
			w.update(x);
		}
		w.reset();
		Assert.isTrue(!w.isReady());
		Assert.floatEquals(0.0, w.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testWedgeBatchEqualsStreaming() {
		var bars = candlesForPivots([110.0, 90.0, 100.0, 94.0, 103.0]);
		assertBatchEqualsStreamingScalar(new Wedge(), new Wedge(), bars);
	}

	// ── ZigZag ───────────────────────────────────────────────────────────────

	// Rust test helper c(price): Candle::new(price, price+0.001, price-0.001, price, 1.0, ts)
	static function zzBar(price:Float, i:Int):Bar {
		return bar(price, price + 0.001, price - 0.001, price, 1.0, i);
	}

	// Rust test helper c_hl(h, l): Candle::new(l, h, l, l, 1.0, ts)
	static function zzBarHl(h:Float, l:Float, i:Int):Bar {
		return bar(l, h, l, l, 1.0, i);
	}

	public function testZigZagRejectsInvalidThreshold() {
		for (t in [0.0, -0.1, 1.0, Math.NaN, Math.POSITIVE_INFINITY]) {
			try {
				new ZigZag(t);
				Assert.fail('Should reject threshold ${t}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testZigZagFirstBarOnlyBootstraps() {
		var zz = new ZigZag(0.05);
		Assert.isNull(zz.update(zzBar(100.0, 0)));
		Assert.isTrue(zz.isReady());
	}

	public function testZigZagConfirmsHighSwingOnThresholdDrop() {
		var zz = new ZigZag(0.10);
		// Up to a peak of 120, then a drop to 100 = 16.7% reversal → confirms.
		Assert.isNull(zz.update(zzBarHl(100.0, 99.5, 0)));
		Assert.isNull(zz.update(zzBarHl(120.0, 119.5, 1)));
		var o = zz.update(zzBarHl(101.0, 100.0, 2));
		Assert.notNull(o);
		Assert.floatEquals(120.0, o.swing);
		Assert.floatEquals(1.0, o.direction);
	}

	public function testZigZagConfirmsLowSwingOnThresholdRise() {
		var zz = new ZigZag(0.10);
		// Up to 120 to seed the high pivot, drop to confirm it as a high,
		// then rise from the new low pivot by 10% to confirm it as a low.
		zz.update(zzBarHl(100.0, 99.5, 0));
		zz.update(zzBarHl(120.0, 119.5, 1));
		zz.update(zzBarHl(101.0, 90.0, 2)); // drop confirms 120-high; new low 90.
		zz.update(zzBarHl(91.0, 90.5, 3));
		// Rise to 100 from low 90 = 11.1% → confirms low.
		var o = zz.update(zzBarHl(100.0, 99.0, 4));
		Assert.notNull(o);
		Assert.floatEquals(90.0, o.swing);
		Assert.floatEquals(-1.0, o.direction);
	}

	public function testZigZagSmallOscillationsYieldNoSwings() {
		var zz = new ZigZag(0.20);
		zz.update(zzBar(100.0, 0));
		for (i in 1...20) {
			// Bounce around 100 ± 5; never crosses the 20% threshold.
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			Assert.isNull(zz.update(zzBar(p, i)));
		}
	}

	public function testZigZagWarmupAndReadyLifecycle() {
		var zz = new ZigZag(0.05);
		Assert.isTrue(!zz.isReady());
		Assert.equals(2, zz.warmupPeriod());
		zz.update(zzBar(100.0, 0));
		Assert.isTrue(zz.isReady());
	}

	public function testZigZagResetClearsState() {
		var zz = new ZigZag(0.10);
		zz.update(zzBarHl(100.0, 99.0, 0));
		zz.update(zzBarHl(120.0, 119.0, 1));
		zz.reset();
		Assert.isTrue(!zz.isReady());
		Assert.isNull(zz.update(zzBarHl(110.0, 109.0, 0)));
	}

	public function testZigZagAccessorsAndMetadata() {
		var zz = new ZigZag(0.05);
		Assert.floatEquals(0.05, zz.threshold());
		Assert.equals(2, zz.warmupPeriod());
		Assert.equals("ZigZag", zz.name());
	}

	public function testZigZagBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var p = 100.0 + Math.sin(i * 0.3) * 15.0;
			zzBar(p, i);
		}];
		var a = new ZigZag(0.05);
		var b = new ZigZag(0.05);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].swing, streamed[i].swing);
				Assert.floatEquals(batched[i].direction, streamed[i].direction);
			}
		}
	}

	// ── TripleTopBottom ──────────────────────────────────────────────────────

	public function testTripleTopBottomAccessorsAndMetadata() {
		var t = new TripleTopBottom();
		Assert.equals("TripleTopBottom", t.name());
		Assert.equals(6, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testTripleTopIsMinusOne() {
		// Three ~equal highs (120, 121, 119) → triple top on the third.
		var t = new TripleTopBottom();
		var out = [for (x in candlesForPivots([120.0, 100.0, 121.0, 99.0, 119.0])) t.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
		for (i in 0...out.length - 1) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTripleBottomIsPlusOne() {
		// Lead high then three ~equal lows (100, 99, 101) → triple bottom.
		var t = new TripleTopBottom();
		var out = [for (x in candlesForPivots([130.0, 100.0, 120.0, 99.0, 122.0, 101.0])) t.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testUnequalThirdPeakDoesNotTrigger() {
		// Third high (140) diverges from the first two (120, 121) → no pattern.
		var t = new TripleTopBottom();
		var out = [for (x in candlesForPivots([120.0, 100.0, 121.0, 99.0, 140.0])) t.update(x)];
		for (v in out) {
			Assert.floatEquals(0.0, v);
		}
	}

	public function testTripleTopBottomResetClearsState() {
		var t = new TripleTopBottom();
		for (x in candlesForPivots([120.0, 100.0, 121.0])) {
			t.update(x);
		}
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testTripleTopBottomBatchEqualsStreaming() {
		var bars = candlesForPivots([120.0, 100.0, 121.0, 99.0, 119.0]);
		assertBatchEqualsStreamingScalar(new TripleTopBottom(), new TripleTopBottom(), bars);
	}

	// ── TowerTopBottom ───────────────────────────────────────────────────────

	/** A tall candle from `open` to `close` (body fills most of the range). */
	static function tallBar(open:Float, close:Float, i:Int):Bar {
		return bar(open, Math.max(open, close) + 0.1, Math.min(open, close) - 0.1, close, 0.0, i);
	}

	/** A small-bodied candle (long shadows, tiny body). */
	static function smallBar(mid:Float, i:Int):Bar {
		return bar(mid, mid + 2.0, mid - 2.0, mid + 0.1, 0.0, i);
	}

	public function testTowerTopBottomAccessorsAndMetadata() {
		var t = new TowerTopBottom();
		Assert.equals(3, t.warmupPeriod());
		Assert.equals("TowerTopBottom", t.name());
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.value());
	}

	public function testTowerFirstTwoBarsSeedWithoutSignal() {
		var t = new TowerTopBottom();
		Assert.floatEquals(0.0, t.update(tallBar(100.0, 110.0, 0)));
		Assert.floatEquals(0.0, t.update(smallBar(105.0, 1)));
		Assert.notNull(t.update(tallBar(110.0, 100.0, 2)));
	}

	public function testTowerTop() {
		// tall bullish, small pause, tall bearish -> top -> -1.
		var t = new TowerTopBottom();
		t.update(tallBar(100.0, 110.0, 0));
		t.update(smallBar(110.0, 1));
		Assert.floatEquals(-1.0, t.update(tallBar(110.0, 100.0, 2)));
	}

	public function testTowerBottom() {
		var t = new TowerTopBottom();
		t.update(tallBar(110.0, 100.0, 0));
		t.update(smallBar(100.0, 1));
		Assert.floatEquals(1.0, t.update(tallBar(100.0, 110.0, 2)));
	}

	public function testTowerSameDirectionIsZero() {
		var t = new TowerTopBottom();
		t.update(tallBar(100.0, 110.0, 0));
		t.update(smallBar(110.0, 1));
		// last bar also bullish -> not a tower -> 0.
		Assert.floatEquals(0.0, t.update(tallBar(110.0, 120.0, 2)));
	}

	public function testTowerNoPauseIsZero() {
		var t = new TowerTopBottom();
		t.update(tallBar(100.0, 110.0, 0));
		t.update(tallBar(110.0, 120.0, 1)); // middle is tall, not a pause
		Assert.floatEquals(0.0, t.update(tallBar(120.0, 110.0, 2)));
	}

	public function testTowerZeroRangeBarHasZeroBodyFraction() {
		// A flat bar (high == low) exercises the zero-range body-fraction branch;
		// it counts as a small "pause" bar, so tall-flat-tall still reverses.
		var t = new TowerTopBottom();
		t.update(tallBar(100.0, 110.0, 0));
		t.update(bar(110.0, 110.0, 110.0, 110.0, 0.0, 1));
		Assert.floatEquals(-1.0, t.update(tallBar(110.0, 100.0, 2)));
	}

	public function testTowerResetClearsState() {
		var t = new TowerTopBottom();
		t.update(tallBar(100.0, 110.0, 0));
		t.update(smallBar(110.0, 1));
		t.update(tallBar(110.0, 100.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(tallBar(100.0, 110.0, 0)));
	}

	public function testTowerBatchEqualsStreaming() {
		var bars = [for (i in 0...30) {
			switch (i % 3) {
				case 0: tallBar(100.0, 110.0, i);
				case 1: smallBar(110.0, i);
				default: tallBar(110.0, 100.0, i);
			}
		}];
		assertBatchEqualsStreamingScalar(new TowerTopBottom(), new TowerTopBottom(), bars);
	}

	// ── RectangleRange ───────────────────────────────────────────────────────

	public function testRectangleRangeAccessorsAndMetadata() {
		var r = new RectangleRange();
		Assert.equals("RectangleRange", r.name());
		Assert.equals(5, r.warmupPeriod());
		Assert.isTrue(!r.isReady());
	}

	public function testRangeBounceOffSupportIsPlusOne() {
		// Flat highs (120, 121), flat lows (100, 99); last pivot a low → +1.
		var r = new RectangleRange();
		var out = [for (x in candlesForPivots([120.0, 100.0, 121.0, 99.0])) r.update(x)];
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testRangeRejectionAtResistanceIsMinusOne() {
		// Same range but ending on a high pivot → -1.
		var r = new RectangleRange();
		var out = [for (x in candlesForPivots([130.0, 100.0, 120.0, 99.0, 121.0])) r.update(x)];
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testTrendingHighsAreNotARectangle() {
		// Rising highs break the flat-resistance requirement → no rectangle.
		var r = new RectangleRange();
		var out = [for (x in candlesForPivots([120.0, 100.0, 140.0, 99.0])) r.update(x)];
		Assert.floatEquals(0.0, out[out.length - 1]);
	}

	public function testRectangleRangeResetClearsState() {
		var r = new RectangleRange();
		for (x in candlesForPivots([120.0, 100.0, 121.0])) {
			r.update(x);
		}
		r.reset();
		Assert.isTrue(!r.isReady());
		Assert.floatEquals(0.0, r.update(bar(99.5, 100.0, 99.5, 99.5, 1.0, 0)));
	}

	public function testRectangleRangeBatchEqualsStreaming() {
		var bars = candlesForPivots([120.0, 100.0, 121.0, 99.0]);
		assertBatchEqualsStreamingScalar(new RectangleRange(), new RectangleRange(), bars);
	}
}

/** Local alias for scalar-output bar-input indicators (batch helper typing). */
private typedef MuseIndicatorBar = musescript.indicators.MuseIndicator<Bar, Float>;
