package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.ew.EwProject.EwProjectBand;
import musescript.ew.EwBenchmark;

/**
 * Phase 0 capture-metric coverage (FIDELITY_AND_BENCHMARK_PLAN.md). Pins the honest semantics of the
 * five-question scorer on synthetic fans/paths BEFORE any real-tape wiring, so a later change to the
 * host or the runner can't silently redefine what "a projection captured the move" means.
 */
class TestEwBenchmark extends Test {
	static inline var EPS = 1e-9;

	static function bar(index:Int, low:Float, high:Float, close:Float):Bar {
		return { open: close, high: high, low: low, close: close, volume: 0, time: index, index: index };
	}

	static function band(pLo:Float, pHi:Float, bLo:Float, bHi:Float):EwProjectBand {
		return { priceLo: pLo, priceHi: pHi, barLo: bLo, barHi: bHi, status: PivotStatus.Projected, kind: "test" };
	}

	static inline function near(a:Float, b:Float):Bool
		return Math.abs(a - b) < 1e-6;

	// ── capture ───────────────────────────────────────────────────────────────────────────────

	public function testPathEnteringZoneIsCapturedWithZeroMargin() {
		// band targets price [100,102] around bar 5; a future bar's range straddles it.
		var fan = [band(100, 102, 4, 5)];
		var futures = [bar(1, 90, 91, 90.5), bar(2, 92, 93, 92.5), bar(3, 95, 96, 95.5),
			bar(4, 98, 99, 98.5), bar(5, 99, 101, 100.5)]; // bar 5 high=101 ∈ [100,102]
		var s = EwBenchmark.scoreAnchor(fan, futures, 1.0);
		Assert.isTrue(s.anyHit);
		Assert.equals(0, s.hitBandIdx);
		Assert.isTrue(near(0.0, s.bestMargin));
		Assert.equals(1, s.bands);
	}

	public function testMissMarginIsAtrNormalizedGap() {
		// band [100,102]; path tops out at high=97 → gap = 100 − 97 = 3; atr = 2 → margin 1.5.
		var fan = [band(100, 102, 4, 5)];
		var futures = [bar(1, 90, 91, 90.5), bar(2, 93, 94, 93.5), bar(3, 95, 96, 95.5),
			bar(4, 96, 97, 96.5), bar(5, 95, 96, 95.5)];
		var s = EwBenchmark.scoreAnchor(fan, futures, 2.0);
		Assert.isFalse(s.anyHit);
		Assert.isTrue(near(1.5, s.bestMargin)); // 3 / 2
		Assert.equals(-1, s.hitBandIdx);
	}

	public function testBestOfFanTakesTheCapturingBand() {
		// two rival interpretations: band0 misses, band1 is hit → anyHit via band1.
		var missing = band(200, 202, 4, 5);
		var hitting = band(100, 102, 4, 5);
		var futures = [bar(4, 98, 99, 98.5), bar(5, 100, 101, 100.5)];
		var s = EwBenchmark.scoreAnchor([missing, hitting], futures, 1.0);
		Assert.isTrue(s.anyHit);
		Assert.equals(1, s.hitBandIdx);
		Assert.isTrue(near(0.0, s.bestMargin));
		Assert.equals(2, s.bands);
	}

	public function testTargetAlreadyPastIsUnscoreableNotAMiss() {
		// band's target bar (2) is before the first future bar (10) → band excluded.
		var fan = [band(100, 102, 1, 2)];
		var futures = [bar(10, 100, 101, 100.5), bar(11, 101, 102, 101.5)];
		var s = EwBenchmark.scoreAnchor(fan, futures, 1.0);
		Assert.equals(0, s.bands);
		Assert.isFalse(s.anyHit);
		Assert.isTrue(Math.isNaN(s.bestMargin));
	}

	public function testTimeBoundBlocksLateCredit() {
		// price only reaches the zone at bar 9, but the band's window ends at bar 5 → not captured.
		var fan = [band(100, 102, 4, 5)];
		var futures = [bar(4, 90, 91, 90.5), bar(5, 92, 93, 92.5), bar(6, 94, 95, 94.5),
			bar(7, 96, 97, 96.5), bar(8, 98, 99, 98.5), bar(9, 100, 101, 100.5)];
		var s = EwBenchmark.scoreAnchor(fan, futures, 1.0);
		Assert.isFalse(s.anyHit); // the bar-9 entry is past the projected window
		Assert.equals(1, s.bands);
	}

	public function testEmptyFanScoresAsUnscoreable() {
		var s = EwBenchmark.scoreAnchor([], [bar(1, 1, 2, 1.5)], 1.0);
		Assert.equals(0, s.bands);
		Assert.isFalse(s.anyHit);
		Assert.isTrue(Math.isNaN(s.bestMargin));
	}

	// ── CRPS ──────────────────────────────────────────────────────────────────────────────────

	public function testCrpsDegeneratesToMaeForSinglePoint() {
		Assert.isTrue(near(3.0, EwBenchmark.crpsEnsemble([7.0], 10.0))); // |7 − 10|
	}

	public function testCrpsZeroWhenEnsembleSitsOnTarget() {
		Assert.isTrue(near(0.0, EwBenchmark.crpsEnsemble([5.0, 5.0, 5.0], 5.0)));
	}

	public function testCrpsRewardsTightAccurateSpreadOverWideOne() {
		// both ensembles are centered on y=10; the tighter one should score lower (better) CRPS.
		var tight = EwBenchmark.crpsEnsemble([9.0, 10.0, 11.0], 10.0);
		var wide = EwBenchmark.crpsEnsemble([2.0, 10.0, 18.0], 10.0);
		Assert.isTrue(tight < wide);
	}

	// ── aggregation ─────────────────────────────────────────────────────────────────────────

	public function testAggregateHitRateExcludesUnscoreable() {
		var hit:AnchorScore = { bands: 3, anyHit: true, bestMargin: 0.0, hitBandIdx: 1, pointErr: 0.2 };
		var miss:AnchorScore = { bands: 2, anyHit: false, bestMargin: 1.5, hitBandIdx: -1, pointErr: 1.1 };
		var dead:AnchorScore = { bands: 0, anyHit: false, bestMargin: Math.NaN, hitBandIdx: -1, pointErr: Math.NaN };
		var g = EwBenchmark.aggregate([hit, miss, dead]);
		Assert.equals(3, g.anchors);
		Assert.equals(2, g.scored);        // dead excluded
		Assert.isTrue(near(0.5, g.hitRate)); // 1 of 2 scoreable
		Assert.isTrue(near(2.5, g.meanBands)); // (3 + 2) / 2
	}

	public function testPercentileLinearInterpolation() {
		Assert.isTrue(near(5.0, EwBenchmark.percentile([0.0, 10.0], 0.5)));
		Assert.isTrue(near(9.0, EwBenchmark.percentile([0.0, 10.0], 0.9)));
		Assert.isTrue(near(4.0, EwBenchmark.percentile([4.0], 0.5)));
		Assert.isTrue(Math.isNaN(EwBenchmark.percentile([], 0.5)));
	}
}
