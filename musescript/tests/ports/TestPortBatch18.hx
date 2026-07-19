package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 18: 10 indicators (market_facilitation_index, martin_ratio,
 * marubozu, mass_index, mcginley_dynamic, median_absolute_deviation,
 * median_channel, matching_low, m2_measure, mat_hold) — standard published
 * formulas (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch18 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── MarketFacilitationIndex ───────────────────────────────────────────

	public function testMarketFacilitationIndexReferenceValue() {
		var mfi = new MarketFacilitationIndex();
		Assert.floatEquals(0.02, mfi.update(bar(10.0, 12.0, 10.0, 11.0, 100.0)), 1e-9);
	}

	// ── MartinRatio ───────────────────────────────────────────────────────

	public function testMartinRatioZeroOnFlatSeries() {
		var mr = new MartinRatio(10);
		var out = null;
		for (i in 0...15) out = mr.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testMartinRatioPositiveWithMinorDipsInAnUptrend() {
		// A monotonic uptrend has zero drawdown -> Ulcer Index is exactly 0 ->
		// the ratio's denominator vanishes, so this needs at least one small
		// dip below the running peak to have a defined (nonzero) Ulcer Index.
		var mr = new MartinRatio(10);
		var equity = [100.0, 102.0, 101.0, 104.0, 103.0, 106.0, 105.0, 108.0, 107.0, 110.0, 109.0];
		var out = null;
		for (e in equity) out = mr.update(e);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── Marubozu ──────────────────────────────────────────────────────────

	public function testMarubozuBullish() {
		var m = new Marubozu();
		Assert.floatEquals(1.0, m.update(bar(10.0, 20.0, 10.0, 20.0, 1.0)));
	}

	public function testMarubozuBearish() {
		var m = new Marubozu();
		Assert.floatEquals(-1.0, m.update(bar(20.0, 20.0, 10.0, 10.0, 1.0)));
	}

	// ── MassIndex ─────────────────────────────────────────────────────────

	public function testMassIndexConstantRangeConverges() {
		var mi = new MassIndex(9, 25);
		var out = null;
		for (i in 0...60) out = mi.update(bar(10.0, 12.0, 8.0, 10.0, 1.0));
		Assert.notNull(out);
		// Constant range -> ema1/ema2 both converge to the same value -> ratio -> 1
		// summed over 25 bars -> MassIndex -> 25.
		Assert.floatEquals(25.0, out, 1e-3);
	}

	// ── McginleyDynamic ───────────────────────────────────────────────────

	public function testMcginleyDynamicFlatSeriesEqualsPrice() {
		var md = new McginleyDynamic(10);
		var out = null;
		for (i in 0...10) out = md.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-9);
	}

	public function testMcginleyDynamicBatchEqualsStreaming() {
		var prices = [for (i in 0...40) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new McginleyDynamic(10), b = new McginleyDynamic(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── MedianAbsoluteDeviation ───────────────────────────────────────────

	public function testMedianAbsoluteDeviationZeroOnFlatSeries() {
		var mad = new MedianAbsoluteDeviation(10);
		var out = null;
		for (i in 0...15) out = mad.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testMedianAbsoluteDeviationReferenceValue() {
		// window [1,2,3,4,5]: median=3, deviations=[2,1,0,1,2], median of those = 1.
		var mad = new MedianAbsoluteDeviation(5);
		var out = null;
		for (p in [1.0, 2.0, 3.0, 4.0, 5.0]) out = mad.update(p);
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	// ── MedianChannel ─────────────────────────────────────────────────────

	public function testMedianChannelReferenceValues() {
		var mc = new MedianChannel(5);
		var out = null;
		for (p in [1.0, 2.0, 3.0, 4.0, 5.0]) out = mc.update(p);
		Assert.notNull(out);
		Assert.floatEquals(5.0, out.upper, 1e-9);
		Assert.floatEquals(3.0, out.median, 1e-9);
		Assert.floatEquals(1.0, out.lower, 1e-9);
	}

	// ── MatchingLow ───────────────────────────────────────────────────────

	public function testMatchingLowBullish() {
		var ml = new MatchingLow();
		ml.update(bar(15.0, 15.5, 9.5, 10.0, 1.0)); // red, close 10
		var out = ml.update(bar(11.0, 11.5, 9.8, 10.02, 1.0)); // red, close ~10
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── M2Measure ─────────────────────────────────────────────────────────

	public function testM2MeasureEqualsRiskFreeOnFlatSeries() {
		var m2 = new M2Measure(10, 0.0, 0.01);
		var out = null;
		for (i in 0...15) out = m2.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testM2MeasurePositiveOnConsistentGains() {
		var m2 = new M2Measure(10, 0.0, 0.01);
		var out = null;
		var price = 100.0;
		for (i in 0...15) { price *= 1.005; out = m2.update(price); }
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── MatHold ───────────────────────────────────────────────────────────

	public function testMatHoldBullish() {
		var mh = new MatHold();
		mh.update(bar(10.0, 20.5, 9.5, 20.0, 1.0)); // bar1: long green, body 10
		mh.update(bar(19.0, 20.0, 17.0, 18.5, 1.0)); // bar2: small, within bar1's range
		mh.update(bar(18.5, 19.5, 17.5, 18.8, 1.0)); // bar3: small, within bar1's range
		mh.update(bar(18.8, 19.8, 17.8, 19.0, 1.0)); // bar4: small, within bar1's range
		var out = mh.update(bar(19.0, 22.0, 18.5, 21.5, 1.0)); // bar5: long green, closes above bar1.high (20.5)
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}
}
