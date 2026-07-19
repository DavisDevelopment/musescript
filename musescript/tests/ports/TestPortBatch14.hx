package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 14: 10 indicators (hilbert_dominant_cycle, ichimoku,
 * identical_three_crows, in_neck, information_ratio, initial_balance,
 * instantaneous_trendline, intraday_intensity, inverse_fisher_transform,
 * inverted_hammer) — standard published formulas (see PORTING.md note on no
 * local Wickra source clone).
 */
class TestPortBatch14 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── HilbertDominantCycle (registry wiring) ──────────────────────────

	public function testHilbertDominantCycleInBand() {
		var hd = new HilbertDominantCycle();
		for (i in 0...200) {
			var out = hd.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) Assert.isTrue(out >= 6.0 && out <= 50.0);
		}
	}

	// ── Ichimoku ──────────────────────────────────────────────────────────

	public function testIchimokuFlatSeriesAllLinesEqualPrice() {
		var ic = new Ichimoku(9, 26, 52);
		var out = null;
		for (i in 0...60) out = ic.update(bar(50.0, 51.0, 49.0, 50.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(50.0, out.tenkan, 1e-9);
		Assert.floatEquals(50.0, out.kijun, 1e-9);
		Assert.floatEquals(50.0, out.senkouA, 1e-9);
		Assert.floatEquals(50.0, out.senkouB, 1e-9);
		Assert.floatEquals(50.0, out.chikou, 1e-9);
	}

	// ── IdenticalThreeCrows ───────────────────────────────────────────────

	public function testIdenticalThreeCrowsBearish() {
		var i3c = new IdenticalThreeCrows();
		i3c.update(bar(20.0, 20.1, 17.9, 18.0, 1.0)); // red, close 18
		i3c.update(bar(18.0, 18.1, 15.9, 16.0, 1.0)); // opens ~18, red, closes near low, lower than 18
		var out = i3c.update(bar(16.0, 16.1, 13.9, 14.0, 1.0)); // opens ~16, red, closes near low, lower than 16
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── InNeck ────────────────────────────────────────────────────────────

	public function testInNeckBearish() {
		var n = new InNeck();
		n.update(bar(20.0, 20.5, 15.0, 15.5, 1.0)); // red bar1: open 20, close 15.5, low 15
		var out = n.update(bar(14.0, 15.6, 13.5, 15.5, 1.0)); // green, opens below 15 (gap), closes at bar1.close
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── InformationRatio ──────────────────────────────────────────────────

	public function testInformationRatioZeroWhenNoTrackingError() {
		var ir = new InformationRatio(10);
		var out = null;
		for (i in 0...15) out = ir.update({ a: 0.01 * i, b: 0.01 * i });
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testInformationRatioPositiveWithConsistentOutperformance() {
		var ir = new InformationRatio(10);
		var out = null;
		for (i in 0...15) out = ir.update({ a: 0.01 * i + 0.002, b: 0.01 * i });
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── InitialBalance ────────────────────────────────────────────────────

	public function testInitialBalanceHoldsFixedAfterWindow() {
		var ib = new InitialBalance(3);
		ib.update(bar(10.0, 12.0, 9.0, 11.0, 1.0));
		ib.update(bar(10.0, 15.0, 8.0, 11.0, 1.0));
		var out1 = ib.update(bar(10.0, 11.0, 9.5, 11.0, 1.0));
		Assert.notNull(out1);
		Assert.floatEquals(15.0, out1.high, 1e-9);
		Assert.floatEquals(8.0, out1.low, 1e-9);
		// A later bar with a much bigger range must NOT change the initial balance.
		var out2 = ib.update(bar(10.0, 100.0, 1.0, 50.0, 1.0));
		Assert.notNull(out2);
		Assert.floatEquals(15.0, out2.high, 1e-9);
		Assert.floatEquals(8.0, out2.low, 1e-9);
	}

	// ── InstantaneousTrendline ────────────────────────────────────────────

	public function testInstantaneousTrendlineFlatSeriesEqualsPrice() {
		var it = new InstantaneousTrendline(0.07);
		var out = null;
		for (i in 0...20) out = it.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-6);
	}

	public function testInstantaneousTrendlineBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new InstantaneousTrendline(0.07), b = new InstantaneousTrendline(0.07);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── IntradayIntensity ─────────────────────────────────────────────────

	public function testIntradayIntensityAllCloseOnHighIsPositive() {
		var ii = new IntradayIntensity(5);
		var out = null;
		for (i in 0...10) out = ii.update(bar(9.0, 11.0, 9.0, 11.0, 100.0));
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testIntradayIntensityAllCloseOnLowIsNegative() {
		var ii = new IntradayIntensity(5);
		var out = null;
		for (i in 0...10) out = ii.update(bar(11.0, 11.0, 9.0, 9.0, 100.0));
		Assert.notNull(out);
		Assert.isTrue(out < 0.0);
	}

	// ── InverseFisherTransform ────────────────────────────────────────────

	public function testInverseFisherTransformInBounds() {
		var ift = new InverseFisherTransform(14);
		for (i in 0...60) {
			var out = ift.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) Assert.isTrue(out >= -1.0 && out <= 1.0);
		}
	}

	public function testInverseFisherTransformZeroOnFlatRsi() {
		// Flat series -> RSI = 50 -> v = 0 -> tanh(0) = 0.
		var ift = new InverseFisherTransform(14);
		var out = null;
		for (i in 0...20) out = ift.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── InvertedHammer ────────────────────────────────────────────────────

	public function testInvertedHammerTrueAfterDowntrend() {
		var ih = new InvertedHammer(3);
		ih.update(bar(20.0, 20.5, 19.5, 20.0, 1.0));
		ih.update(bar(19.0, 19.5, 17.0, 17.5, 1.0));
		ih.update(bar(17.0, 17.2, 14.0, 14.5, 1.0));
		// small body near bottom, long upper shadow, undercuts context lows.
		var out = ih.update(bar(13.0, 18.0, 12.8, 13.1, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}
}
