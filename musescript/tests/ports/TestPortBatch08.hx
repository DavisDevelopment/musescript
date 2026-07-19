package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 08: 10 indicators (doji, dragonfly_doji, donchian, donchian_stop,
 * dpo, dx, ease_of_movement, ehma, detrended_std_dev, distance_ssd) —
 * standard published formulas (see PORTING.md note on no local Wickra
 * source clone).
 */
class TestPortBatch08 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Doji / DragonflyDoji ──────────────────────────────────────────────

	public function testDojiTrue() {
		var d = new Doji();
		Assert.floatEquals(1.0, d.update(bar(10.0, 12.0, 8.0, 10.01, 1.0)));
	}

	public function testDojiFalseOnLargeBody() {
		var d = new Doji();
		Assert.floatEquals(0.0, d.update(bar(10.0, 12.0, 8.0, 11.5, 1.0)));
	}

	public function testDragonflyDojiTrue() {
		// body negligible near the high, long lower shadow.
		var d = new DragonflyDoji();
		Assert.floatEquals(1.0, d.update(bar(20.0, 20.0, 10.0, 19.9, 1.0)));
	}

	public function testDragonflyDojiFalseOnRegularDoji() {
		// centered doji: shadows roughly balanced, not dragonfly-shaped.
		var d = new DragonflyDoji();
		Assert.floatEquals(0.0, d.update(bar(15.0, 20.0, 10.0, 15.05, 1.0)));
	}

	// ── Donchian / DonchianStop ───────────────────────────────────────────

	public function testDonchianReferenceValues() {
		var d = new Donchian(3);
		d.update(bar(10.0, 12.0, 9.0, 11.0, 1.0));
		d.update(bar(10.0, 15.0, 8.0, 11.0, 1.0));
		var out = d.update(bar(10.0, 11.0, 7.0, 11.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(15.0, out.upper, 1e-9);
		Assert.floatEquals(7.0, out.lower, 1e-9);
		Assert.floatEquals(11.0, out.middle, 1e-9);
	}

	public function testDonchianStopExcludesCurrentBar() {
		// DonchianStop needs `period` PRIOR bars fully collected before it can
		// emit (warmupPeriod = period + 1), and never reads the current bar's
		// own extreme into its own stop.
		var d = new DonchianStop(3);
		d.update(bar(10.0, 12.0, 9.0, 11.0, 1.0));
		d.update(bar(10.0, 13.0, 8.0, 11.0, 1.0));
		d.update(bar(10.0, 9.0, 7.5, 8.0, 1.0));
		var out = d.update(bar(10.0, 999.0, -999.0, 11.0, 1.0)); // extreme current bar must not leak in
		Assert.notNull(out);
		Assert.floatEquals(13.0, out.shortStop, 1e-9); // highest of the first three bars only
		Assert.floatEquals(7.5, out.longStop, 1e-9);
	}

	public function testDonchianBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0);
		}];
		var a = new Donchian(10), b = new Donchian(10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.floatEquals(batched[i].upper, streamed[i].upper, 1e-9);
				Assert.floatEquals(batched[i].lower, streamed[i].lower, 1e-9);
			}
		}
	}

	// ── Dpo ───────────────────────────────────────────────────────────────

	public function testDpoZeroOnFlatSeries() {
		var d = new Dpo(10);
		var out = null;
		for (i in 0...20) out = d.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testDpoBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new Dpo(10), b = new Dpo(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Dx ────────────────────────────────────────────────────────────────

	public function testDxZeroTrueRangeYieldsZero() {
		var dx = new Dx(5);
		var last = null;
		for (i in 0...20) last = dx.update(bar(10.0, 10.0, 10.0, 10.0, 1.0));
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-9);
	}

	public function testDxInBounds() {
		var dx = new Dx(14);
		for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var out = dx.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
			if (out != null) Assert.isTrue(out >= 0.0 && out <= 100.0 + 1e-9);
		}
	}

	// ── EaseOfMovement ────────────────────────────────────────────────────

	public function testEaseOfMovementZeroOnConstantMidpoint() {
		var e = new EaseOfMovement(5);
		var out = null;
		for (i in 0...15) out = e.update(bar(10.0, 12.0, 8.0, 10.0, 1000.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── Ehma ──────────────────────────────────────────────────────────────

	public function testEhmaFlatSeriesConvergesToConstant() {
		var e = new Ehma(10);
		var out = null;
		for (i in 0...40) out = e.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-6);
	}

	public function testEhmaBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new Ehma(10), b = new Ehma(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── DetrendedStdDev ───────────────────────────────────────────────────

	public function testDetrendedStdDevZeroOnFlatSeries() {
		var d = new DetrendedStdDev(5);
		var out = null;
		for (i in 0...15) out = d.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testDetrendedStdDevZeroOnPerfectLinearTrend() {
		// A perfectly linear ramp detrends to a CONSTANT residual each step
		// (SMA lags a fixed amount behind), so the rolling stddev of the
		// detrended series is 0.
		var d = new DetrendedStdDev(5);
		var out = null;
		for (i in 1...30) out = d.update(i * 2.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	// ── DistanceSsd ───────────────────────────────────────────────────────

	public function testDistanceSsdZeroWhenSeriesIdentical() {
		var d = new DistanceSsd(5);
		var out = null;
		for (i in 0...10) out = d.update({ a: 1.0 * i, b: 1.0 * i });
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testDistanceSsdReferenceValue() {
		// constant diff of 2 each bar over a window of 3 -> SSD = 3 * 2^2 = 12.
		var d = new DistanceSsd(3);
		var out = null;
		for (i in 0...5) out = d.update({ a: 10.0, b: 8.0 });
		Assert.notNull(out);
		Assert.floatEquals(12.0, out, 1e-9);
	}

	public function testDistanceSsdBatchEqualsStreaming() {
		var inputs = [for (i in 0...40) { a: Math.sin(i * 0.2), b: Math.sin(i * 0.2 + 0.5) }];
		var a1 = new DistanceSsd(10), a2 = new DistanceSsd(10);
		var batched = IndicatorBatch.run(a1, inputs);
		var streamed = [for (x in inputs) a2.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
