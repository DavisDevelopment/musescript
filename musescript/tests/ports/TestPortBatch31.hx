package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 31: 5 Fibonacci and pattern indicators (fib_confluence, fib_fan,
 * fib_projection, fib_time_zones, flag_pennant).
 * Known-value cases transcribed from Rust fixtures; batch_equals_streaming
 * verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch31 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function c(high:Float, low:Float, ts:Int):Bar {
		return bar(low, high, low, low, 1.0, ts);
	}

	/**
	 * Generate bars that produce the given pivot prices.
	 * Alternates high/low starting with high; each pivot triggers a reversal.
	 */
	static function candlesForPivots(pivots:Array<Float>):Array<Bar> {
		var out:Array<Bar> = [];
		out.push(c(pivots[0], pivots[0] * 0.999, 0));
		var ts = 0;
		for (k in 0...pivots.length) {
			ts++;
			var price = pivots[k];
			var isHigh = (k % 2 == 0);
			var next = (k + 1 < pivots.length) ? pivots[k + 1]
				: (isHigh ? price * 0.90 : price * 1.10);
			var candle = isHigh
				? c(price * 0.99, next, ts)
				: c(next, price * 1.01, ts);
			out.push(candle);
		}
		return out;
	}

	// ── FibConfluence ────────────────────────────────────────────────────────

	public function testFibConfluenceAccessorsAndMetadata() {
		var ind = new FibConfluence();
		Assert.equals("FIBCONF", ind.name());
		Assert.equals(3, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
	}

	public function testFibConfluenceNoOutputBeforeTwoLegs() {
		var ind = new FibConfluence();
		var bars = candlesForPivots([200.0, 100.0]);
		var outputs:Array<Dynamic> = [];
		for (b in bars) outputs.push(ind.update(b));
		for (out in outputs) Assert.isNull(out);
		Assert.isFalse(ind.isReady());
	}

	public function testFibConfluencePicksDensestCluster() {
		// Legs 200->100 and 100->160. The 38.2% of each (138.2 and ~137.08)
		// sit within 3% of each other and form the densest cluster (strength 2).
		var ind = new FibConfluence();
		var bars = candlesForPivots([200.0, 100.0, 160.0]);
		var last:Dynamic = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.isTrue(ind.isReady());
		Assert.floatEquals(2.0, last.strength, 1e-9);
		var want = (138.2 + (160.0 + 0.382 * (100.0 - 160.0))) / 2.0;
		Assert.floatEquals(want, last.price, 1e-9);
	}

	public function testFibConfluenceResetClearsState() {
		var ind = new FibConfluence();
		var bars = candlesForPivots([200.0, 100.0, 160.0]);
		for (b in bars) ind.update(b);
		Assert.isTrue(ind.isReady());
		ind.reset();
		Assert.isFalse(ind.isReady());
		var c = bar(99.5, 100.0, 99.5, 99.5, 1.0, 0);
		Assert.isNull(ind.update(c));
	}

	public function testFibConfluenceBatchEqualsStreaming() {
		var bars = candlesForPivots([200.0, 100.0, 160.0, 120.0]);
		var a = new FibConfluence(), b = new FibConfluence();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].price, streamed[i].price, 1e-9);
				Assert.floatEquals(batched[i].strength, streamed[i].strength, 1e-9);
			}
		}
	}

	// ── FibFan ──────────────────────────────────────────────────────────────

	public function testFibFanAccessorsAndMetadata() {
		var ind = new FibFan();
		Assert.equals("FIBFAN", ind.name());
		Assert.equals(2, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
	}

	public function testFibFanNoOutputBeforeTwoPivots() {
		var ind = new FibFan();
		var bars = [c(200.0, 199.0, 0), c(190.0, 150.0, 1)];
		var outputs:Array<Dynamic> = [];
		for (b in bars) outputs.push(ind.update(b));
		for (out in outputs) Assert.isNull(out);
		Assert.isFalse(ind.isReady());
	}

	public function testFibFanFanLinesOpenWithElapsedTime() {
		var ind = new FibFan();
		var bars = [
			c(200.0, 199.0, 0),  // bootstrap high @200 (bar 0)
			c(190.0, 160.0, 1),  // confirm high @200, low candidate @160
			c(150.0, 100.0, 2),  // extend low to 100 (bar 2)
			c(110.0, 105.0, 3),  // confirm low @100 -> two pivots
		];
		var last:Dynamic = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.isTrue(ind.isReady());
		// progress = (3 - 0) / (2 - 0) = 1.5; line(r) = 200 + r*(-100)*1.5.
		Assert.floatEquals(200.0 - 0.382 * 150.0, last.fan382, 1e-9);
		Assert.floatEquals(125.0, last.fan500, 1e-9);
		Assert.floatEquals(200.0 - 0.618 * 150.0, last.fan618, 1e-9);
	}

	public function testFibFanResetClearsState() {
		var ind = new FibFan();
		var bars = [
			c(200.0, 199.0, 0),
			c(190.0, 160.0, 1),
			c(150.0, 100.0, 2),
			c(110.0, 105.0, 3),
		];
		for (b in bars) ind.update(b);
		Assert.isTrue(ind.isReady());
		ind.reset();
		Assert.isFalse(ind.isReady());
		var out = ind.update(c(100.0, 99.5, 0));
		Assert.isNull(out);
	}

	public function testFibFanBatchEqualsStreaming() {
		var bars = [
			c(200.0, 199.0, 0),
			c(190.0, 160.0, 1),
			c(150.0, 100.0, 2),
			c(110.0, 105.0, 3),
		];
		var a = new FibFan(), b = new FibFan();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].fan382, streamed[i].fan382, 1e-9);
				Assert.floatEquals(batched[i].fan500, streamed[i].fan500, 1e-9);
				Assert.floatEquals(batched[i].fan618, streamed[i].fan618, 1e-9);
			}
		}
	}

	// ── FibProjection ────────────────────────────────────────────────────────

	public function testFibProjectionAccessorsAndMetadata() {
		var ind = new FibProjection();
		Assert.equals("FIBPROJ", ind.name());
		Assert.equals(3, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
	}

	public function testFibProjectionNoOutputBeforeThreePivots() {
		var ind = new FibProjection();
		var bars = candlesForPivots([200.0, 100.0]);
		var outputs:Array<Dynamic> = [];
		for (b in bars) outputs.push(ind.update(b));
		for (out in outputs) Assert.isNull(out);
		Assert.isFalse(ind.isReady());
	}

	public function testFibProjectionMeasuredMoveFromThreePivots() {
		// A = 200 (high), B = 160 (low), C = 190 (high). A->B = -40, projected
		// down from C.
		var ind = new FibProjection();
		var bars = candlesForPivots([200.0, 160.0, 190.0]);
		var last:Dynamic = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.isTrue(ind.isReady());
		var a = 200.0, b = 160.0, c = 190.0;
		Assert.floatEquals(c + 0.618 * (b - a), last.level618, 1e-9);
		Assert.floatEquals(c + (b - a), last.level1000, 1e-9);
		Assert.floatEquals(c + 1.618 * (b - a), last.level1618, 1e-9);
		Assert.floatEquals(c + 2.618 * (b - a), last.level2618, 1e-9);
	}

	public function testFibProjectionResetClearsState() {
		var ind = new FibProjection();
		var bars = candlesForPivots([200.0, 160.0, 190.0]);
		for (b in bars) ind.update(b);
		Assert.isTrue(ind.isReady());
		ind.reset();
		Assert.isFalse(ind.isReady());
		var c = bar(99.5, 100.0, 99.5, 99.5, 1.0, 0);
		Assert.isNull(ind.update(c));
	}

	public function testFibProjectionBatchEqualsStreaming() {
		var bars = candlesForPivots([200.0, 160.0, 190.0, 150.0]);
		var a = new FibProjection(), b = new FibProjection();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].level618, streamed[i].level618, 1e-9);
				Assert.floatEquals(batched[i].level1000, streamed[i].level1000, 1e-9);
				Assert.floatEquals(batched[i].level1618, streamed[i].level1618, 1e-9);
				Assert.floatEquals(batched[i].level2618, streamed[i].level2618, 1e-9);
			}
		}
	}

	// ── FibTimeZones ─────────────────────────────────────────────────────────

	public function testFibTimeZonesAccessorsAndMetadata() {
		var ind = new FibTimeZones();
		Assert.equals("FIBTIMEZ", ind.name());
		Assert.equals(2, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
	}

	public function testFibTimeZonesNoOutputBeforeFirstPivot() {
		var ind = new FibTimeZones();
		var out = ind.update(c(200.0, 199.0, 0));
		Assert.isNull(out);
		Assert.isFalse(ind.isReady());
	}

	public function testFibTimeZonesFlagsZonesAndCountsToNext() {
		var ind = new FibTimeZones();
		var bars:Array<Bar> = [c(200.0, 199.0, 0), c(190.0, 150.0, 1)];
		for (i in 2...6) bars.push(c(155.0, 151.0, i));

		var out:Array<Dynamic> = [];
		for (b in bars) out.push(ind.update(b));

		Assert.isNull(out[0]); // bootstrap, no pivot yet
		Assert.isTrue(ind.isReady());

		// out[i] is reported at current bar i; anchor at bar 0 → distance = i.
		var d1 = out[1];
		Assert.notNull(d1);
		Assert.floatEquals(1.0, d1.onZone, 1e-9);  // distance 1 → a zone
		Assert.floatEquals(1.0, d1.barsToNext, 1e-9); // next zone at 2

		var d4 = out[4];
		Assert.notNull(d4);
		Assert.floatEquals(0.0, d4.onZone, 1e-9);  // distance 4 → not a zone
		Assert.floatEquals(1.0, d4.barsToNext, 1e-9); // next zone at 5

		var d5 = out[5];
		Assert.notNull(d5);
		Assert.floatEquals(1.0, d5.onZone, 1e-9);  // distance 5 → a zone
		Assert.floatEquals(3.0, d5.barsToNext, 1e-9); // next zone at 8
	}

	public function testFibTimeZonesResetClearsState() {
		var ind = new FibTimeZones();
		var bars:Array<Bar> = [c(200.0, 199.0, 0), c(190.0, 150.0, 1)];
		for (i in 2...6) bars.push(c(155.0, 151.0, i));
		for (b in bars) ind.update(b);
		Assert.isTrue(ind.isReady());
		ind.reset();
		Assert.isFalse(ind.isReady());
		var out = ind.update(c(100.0, 99.5, 0));
		Assert.isNull(out);
	}

	public function testFibTimeZonesBatchEqualsStreaming() {
		var bars:Array<Bar> = [c(200.0, 199.0, 0), c(190.0, 150.0, 1)];
		for (i in 2...6) bars.push(c(155.0, 151.0, i));
		var a = new FibTimeZones(), b = new FibTimeZones();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.notNull(streamed[i]);
				Assert.floatEquals(batched[i].onZone, streamed[i].onZone, 1e-9);
				Assert.floatEquals(batched[i].barsToNext, streamed[i].barsToNext, 1e-9);
			}
		}
	}

	// ── FlagPennant ──────────────────────────────────────────────────────────

	public function testFlagPennantAccessorsAndMetadata() {
		var ind = new FlagPennant();
		Assert.equals("FLAGPENN", ind.name());
		Assert.equals(4, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
	}

	public function testFlagPennantBullFlagIsOnePointZero() {
		// Up-pole 100 → 140 (40), shallow pullback to 130 (10 < 20) → bull flag.
		var bars = candlesForPivots([150.0, 100.0, 140.0, 130.0]);
		var ind = new FlagPennant();
		var last:Null<Float> = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.floatEquals(1.0, last, 1e-9);
	}

	public function testFlagPennantBearFlagIsMinusOnePointZero() {
		// Down-pole 140 → 100 (40), shallow pullback to 110 (10 < 20) → bear flag.
		var bars = candlesForPivots([140.0, 100.0, 110.0]);
		var ind = new FlagPennant();
		var last:Null<Float> = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.floatEquals(-1.0, last, 1e-9);
	}

	public function testFlagPennantDeepPullbackIsNotAFlag() {
		// Pole 100 → 140 (40) but pullback to 104 (36 > 20) → not a flag.
		var bars = candlesForPivots([150.0, 100.0, 140.0, 104.0]);
		var ind = new FlagPennant();
		var last:Null<Float> = null;
		for (b in bars) last = ind.update(b);
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-9);
	}

	public function testFlagPennantResetClearsState() {
		var ind = new FlagPennant();
		var bars = candlesForPivots([150.0, 100.0, 140.0]);
		for (b in bars) ind.update(b);
		ind.reset();
		Assert.isFalse(ind.isReady());
		var c = bar(99.5, 100.0, 99.5, 99.5, 1.0, 0);
		var out = ind.update(c);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testFlagPennantBatchEqualsStreaming() {
		var bars = candlesForPivots([150.0, 100.0, 140.0, 130.0]);
		var a = new FlagPennant(), b = new FlagPennant();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.notNull(batched[i]);
			Assert.notNull(streamed[i]);
			Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}
}
