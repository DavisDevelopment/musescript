package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 06: 10 indicators (calmar_ratio, candle_volume, center_of_gravity,
 * cfo, chaikin_oscillator, chaikin_volatility, classic_pivots,
 * close_vs_open, cmf, coefficient_of_variation) — standard published
 * formulas (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch06 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── CandleVolume / CloseVsOpen ───────────────────────────────────────

	public function testCandleVolumePassesThrough() {
		var cv = new CandleVolume();
		Assert.floatEquals(1234.0, cv.update(bar(10.0, 11.0, 9.0, 10.5, 1234.0)));
	}

	public function testCloseVsOpenPositiveOnGreenBar() {
		var c = new CloseVsOpen();
		// (11 - 10) / 10 * 100 = 10
		Assert.floatEquals(10.0, c.update(bar(10.0, 12.0, 9.0, 11.0, 1.0)), 1e-9);
	}

	public function testCloseVsOpenNegativeOnRedBar() {
		var c = new CloseVsOpen();
		Assert.floatEquals(-10.0, c.update(bar(10.0, 11.0, 8.0, 9.0, 1.0)), 1e-9);
	}

	// ── CenterOfGravity ───────────────────────────────────────────────────

	public function testCenterOfGravityConstantSeriesTracksMidpoint() {
		// Constant price p: COG = -(sum(weight*p))/(sum(p)) = -(mean weight) = -(n+1)/2.
		var cog = new CenterOfGravity(5);
		var out = null;
		for (i in 0...10) out = cog.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(-3.0, out, 1e-9); // -(5+1)/2
	}

	public function testCenterOfGravityBatchEqualsStreaming() {
		var prices = [for (i in 0...40) 100.0 + Math.sin(i * 0.3) * 5.0];
		var a = new CenterOfGravity(8), b = new CenterOfGravity(8);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Cfo ───────────────────────────────────────────────────────────────

	public function testCfoZeroOnPerfectLinearTrend() {
		// A perfectly linear series' regression forecast exactly matches price -> CFO = 0.
		var cfo = new Cfo(10);
		var out = null;
		for (i in 1...21) out = cfo.update(i * 2.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testCfoBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new Cfo(14), b = new Cfo(14);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── CoefficientOfVariation ───────────────────────────────────────────

	public function testCoefficientOfVariationZeroOnFlatSeries() {
		var cv = new CoefficientOfVariation(5);
		var out = null;
		for (i in 0...10) out = cv.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testCoefficientOfVariationNonNegative() {
		var cv = new CoefficientOfVariation(10);
		for (i in 0...40) {
			var out = cv.update(100.0 + Math.sin(i * 0.4) * 8.0);
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	// ── CalmarRatio ───────────────────────────────────────────────────────

	public function testCalmarRatioNoDrawdownIsZero() {
		var equity = [for (i in 1...21) 100.0 + i];
		var cr = new CalmarRatio(20);
		var out = null;
		for (e in equity) out = cr.update(e);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testCalmarRatioPositiveWithRecoveredDrawdown() {
		var equity = [100.0, 110.0, 90.0, 120.0, 130.0];
		var cr = new CalmarRatio(5);
		var out = null;
		for (e in equity) out = cr.update(e);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── Cmf ───────────────────────────────────────────────────────────────

	public function testCmfAllCloseOnHighIsOne() {
		// Every bar closes on its high -> MFM = +1 each bar -> CMF = 1.
		var cmf = new Cmf(5);
		var out = null;
		for (i in 0...10) out = cmf.update(bar(9.0, 11.0, 9.0, 11.0, 100.0));
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	public function testCmfAllCloseOnLowIsNegativeOne() {
		var cmf = new Cmf(5);
		var out = null;
		for (i in 0...10) out = cmf.update(bar(11.0, 11.0, 9.0, 9.0, 100.0));
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out, 1e-9);
	}

	public function testCmfBatchEqualsStreaming() {
		var bars = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(base, base + 2.0, base - 2.0, base + 0.5, 100.0 + i);
		}];
		var a = new Cmf(14), b = new Cmf(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── ChaikinOscillator / ChaikinVolatility ────────────────────────────

	public function testChaikinOscillatorFlatCandlesConvergeToZero() {
		// Zero-range bars -> ADL never moves -> both EMAs converge to the same
		// constant -> oscillator settles at 0.
		var co = new ChaikinOscillator(3, 10);
		var last = null;
		for (i in 0...30) last = co.update(bar(10.0, 10.0, 10.0, 10.0, 100.0));
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-6);
	}

	public function testChaikinOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.2) * 5.0;
			bar(base, base + 1.5, base - 1.5, base + 0.3, 100.0 + i);
		}];
		var a = new ChaikinOscillator(3, 10), b = new ChaikinOscillator(3, 10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	public function testChaikinVolatilityZeroOnConstantRange() {
		// Constant H-L range every bar -> smoothed range never changes -> CV = 0.
		var cv = new ChaikinVolatility(5, 5);
		var last = null;
		for (i in 0...20) last = cv.update(bar(10.0, 12.0, 8.0, 10.0, 1.0));
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-6);
	}

	// ── ClassicPivots / CamarillaPivots-style lag ────────────────────────

	public function testClassicPivotsFirstBarIsNull() {
		var cp = new ClassicPivots();
		Assert.isNull(cp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0)));
	}

	public function testClassicPivotsReferenceValues() {
		// prev bar: H=12, L=8, C=11 -> pivot = 31/3.
		var cp = new ClassicPivots();
		cp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		var out = cp.update(bar(11.0, 13.0, 10.0, 12.0, 1.0));
		Assert.notNull(out);
		var pivot = (12.0 + 8.0 + 11.0) / 3.0;
		Assert.floatEquals(pivot, out.pivot, 1e-9);
		Assert.floatEquals(2.0 * pivot - 8.0, out.r1, 1e-9);
		Assert.floatEquals(2.0 * pivot - 12.0, out.s1, 1e-9);
		Assert.floatEquals(pivot + 4.0, out.r2, 1e-9);
		Assert.floatEquals(pivot - 4.0, out.s2, 1e-9);
	}

	// ── CalmarRatio/Cfo/CoV registration safety net covered by
	// TestIndicatorPorts.testEveryRegisteredIndicatorIsCallable.
}
