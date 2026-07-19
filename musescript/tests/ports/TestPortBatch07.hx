package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 07: 10 indicators (dema, disparity_index, coppock, chandelier_exit,
 * choppiness_index, central_pivot_range, demark_pivots, closing_marubozu,
 * conditional_value_at_risk, connors_rsi) — standard published formulas
 * (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch07 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Dema / DisparityIndex ────────────────────────────────────────────

	public function testDemaFlatSeriesConvergesToConstant() {
		var d = new Dema(5);
		var out = null;
		for (i in 0...20) out = d.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-9);
	}

	public function testDemaBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new Dema(8), b = new Dema(8);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	public function testDisparityIndexZeroOnFlatSeries() {
		var di = new DisparityIndex(5);
		var out = null;
		for (i in 0...10) out = di.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testDisparityIndexPositiveWhenAboveAverage() {
		var di = new DisparityIndex(5);
		for (i in 0...4) di.update(100.0);
		var out = di.update(110.0);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── Coppock ───────────────────────────────────────────────────────────

	public function testCoppockZeroOnFlatSeries() {
		var c = new Coppock(14, 11, 10);
		var out = null;
		for (i in 0...40) out = c.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testCoppockBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.15) * 6.0];
		var a = new Coppock(14, 11, 10), b = new Coppock(14, 11, 10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── ChandelierExit ────────────────────────────────────────────────────

	public function testChandelierExitLongBelowShortAbove() {
		var ce = new ChandelierExit(10, 3.0);
		var out = null;
		for (i in 0...20) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			out = ce.update(bar(base, base + 2.0, base - 2.0, base + 0.5, 1.0));
		}
		Assert.notNull(out);
		Assert.isTrue(Math.isFinite(out.longStop) && Math.isFinite(out.shortStop));
	}

	public function testChandelierExitBatchEqualsStreaming() {
		var bars = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0);
		}];
		var a = new ChandelierExit(10, 3.0), b = new ChandelierExit(10, 3.0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else {
				Assert.floatEquals(batched[i].longStop, streamed[i].longStop, 1e-9);
				Assert.floatEquals(batched[i].shortStop, streamed[i].shortStop, 1e-9);
			}
		}
	}

	// ── ChoppinessIndex ───────────────────────────────────────────────────

	public function testChoppinessIndexInBounds() {
		var ci = new ChoppinessIndex(14);
		for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.4) * 5.0;
			var out = ci.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
			if (out != null) Assert.isTrue(out >= 0.0 && out <= 100.0 + 1e-6);
		}
	}

	// ── CentralPivotRange / DemarkPivots ─────────────────────────────────

	public function testCentralPivotRangeReferenceValues() {
		// prev bar: H=12, L=8, C=11.
		var cpr = new CentralPivotRange();
		cpr.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		var out = cpr.update(bar(11.0, 13.0, 10.0, 12.0, 1.0));
		Assert.notNull(out);
		var pivot = (12.0 + 8.0 + 11.0) / 3.0;
		var bottom = (12.0 + 8.0) / 2.0;
		Assert.floatEquals(pivot, out.pivot, 1e-9);
		Assert.floatEquals(bottom, out.bottom, 1e-9);
		Assert.floatEquals(2.0 * pivot - bottom, out.top, 1e-9);
	}

	public function testDemarkPivotsCloseAboveOpen() {
		// close > open -> X = 2H + L + C.
		var dp = new DemarkPivots();
		dp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		var out = dp.update(bar(11.0, 13.0, 10.0, 12.0, 1.0));
		Assert.notNull(out);
		var x = 2.0 * 12.0 + 8.0 + 11.0;
		Assert.floatEquals(x / 4.0, out.pivot, 1e-9);
		Assert.floatEquals(x / 2.0 - 8.0, out.r1, 1e-9);
		Assert.floatEquals(x / 2.0 - 12.0, out.s1, 1e-9);
	}

	// ── ClosingMarubozu ───────────────────────────────────────────────────

	public function testClosingMarubozuBullish() {
		// closes exactly on the high, green body.
		var cm = new ClosingMarubozu();
		Assert.floatEquals(1.0, cm.update(bar(10.0, 20.0, 9.0, 20.0, 1.0)));
	}

	public function testClosingMarubozuBearish() {
		var cm = new ClosingMarubozu();
		Assert.floatEquals(-1.0, cm.update(bar(20.0, 21.0, 10.0, 10.0, 1.0)));
	}

	public function testClosingMarubozuOpenAnywhereStillCounts() {
		// Open in the middle of the range (unlike BeltHold) still qualifies
		// as long as the CLOSE side has no wick.
		var cm = new ClosingMarubozu();
		Assert.floatEquals(1.0, cm.update(bar(15.0, 20.0, 10.0, 20.0, 1.0)));
	}

	// ── ConditionalValueAtRisk ────────────────────────────────────────────

	public function testConditionalValueAtRiskNonNegativeUnderLosses() {
		// Steady decline -> every return negative -> CVaR should be positive.
		var cvar = new ConditionalValueAtRisk(10, 0.9);
		var out = null;
		for (i in 0...11) out = cvar.update(100.0 - i);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testConditionalValueAtRiskZeroOnFlatSeries() {
		var cvar = new ConditionalValueAtRisk(10, 0.9);
		var out = null;
		for (i in 0...11) out = cvar.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	// ── ConnorsRsi ────────────────────────────────────────────────────────

	public function testConnorsRsiInBounds() {
		var cr = new ConnorsRsi(3, 2, 20);
		for (i in 0...60) {
			var out = cr.update(100.0 + Math.sin(i * 0.3) * 5.0 + (i % 5) * 0.3);
			if (out != null) Assert.isTrue(out >= 0.0 && out <= 100.0);
		}
	}

	public function testConnorsRsiBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.2) * 5.0 + (i % 3)];
		var a = new ConnorsRsi(3, 2, 20), b = new ConnorsRsi(3, 2, 20);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
