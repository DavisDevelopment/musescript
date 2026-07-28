package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.ew.auction.VolumeProfile;

/**
 * Pure VolumeProfile: histogram → POC + value-area enclosing p% of volume.
 */
class TestVolumeProfile extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return {open: o, high: h, low: l, close: c, volume: v, time: i, index: i};
	}

	public function testFlatWindowCollapses() {
		var bars = [
			for (i in 0...5) bar(100, 100, 100, 100, 1000, i)
		];
		var lv = VolumeProfile.fromBars(bars, 5, 20, 0.70);
		Assert.floatEquals(100.0, lv.poc, 1e-12);
		Assert.floatEquals(100.0, lv.vaHigh, 1e-12);
		Assert.floatEquals(100.0, lv.vaLow, 1e-12);
		Assert.floatEquals(1.0, lv.valueAreaVolFrac, 1e-12);
	}

	public function testConcentratedVolumeLocatesPoc() {
		// Four light bars around 100, one heavy single-print at 110.
		var bars = [
			bar(100, 101, 99, 100, 100, 0),
			bar(100, 101, 99, 100, 100, 1),
			bar(100, 101, 99, 100, 100, 2),
			bar(100, 101, 99, 100, 100, 3),
			bar(110, 110, 110, 110, 10000, 4)
		];
		var lv = VolumeProfile.fromBars(bars, 5, 50, 0.70);
		Assert.isTrue(lv.poc >= 109.5 && lv.poc <= 110.5, 'POC ${lv.poc} not near 110');
		Assert.isTrue(lv.vaHigh >= lv.poc);
		Assert.isTrue(lv.vaLow <= lv.poc);
		Assert.isTrue(lv.valueAreaVolFrac >= 0.70 - 1e-9);
		Assert.isTrue(lv.valueAreaVolFrac <= 1.0 + 1e-9);
	}

	public function testValueAreaBracketsPoc() {
		var bars = [for (i in 0...30) {
			var mid = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(mid, mid + 3, mid - 3, mid, 1000 + i * 10, i);
		}];
		var lv = VolumeProfile.fromBars(bars, 20, 40, 0.70);
		Assert.isTrue(Math.isFinite(lv.poc));
		Assert.isTrue(lv.vaHigh >= lv.poc, 'VAH ${lv.vaHigh} < POC ${lv.poc}');
		Assert.isTrue(lv.vaLow <= lv.poc, 'VAL ${lv.vaLow} > POC ${lv.poc}');
		Assert.isTrue(lv.valueAreaVolFrac >= 0.70 - 1e-9);
	}

	public function testEndInclusiveIsCausal() {
		var bars = [for (i in 0...10) bar(100 + i, 105 + i, 95 + i, 100 + i, 1000, i)];
		var early = VolumeProfile.fromBars(bars, 5, 20, 0.70, 4);
		var late = VolumeProfile.fromBars(bars, 5, 20, 0.70, 9);
		Assert.isTrue(Math.isFinite(early.poc));
		Assert.isTrue(Math.isFinite(late.poc));
		// Different windows → generally different POC (late window is higher).
		Assert.isTrue(late.poc > early.poc, 'late POC ${late.poc} should exceed early ${early.poc}');
	}

	public function testZeroVolumeHandled() {
		var bars = [
			bar(50, 60, 40, 50, 0, 0),
			bar(50, 60, 40, 50, 0, 1),
			bar(50, 60, 40, 50, 0, 2)
		];
		var lv = VolumeProfile.fromBars(bars, 3, 10, 0.70);
		Assert.isTrue(Math.isFinite(lv.poc));
		Assert.isTrue(lv.vaHigh >= lv.vaLow);
		Assert.floatEquals(0.0, lv.valueAreaVolFrac, 1e-12);
	}

	public function testDeterministic() {
		var bars = [for (i in 0...25) {
			var mid = 200.0 + Math.sin(i * 0.2) * 8.0;
			bar(mid, mid + 2, mid - 2, mid, 500 + i, i);
		}];
		var a = VolumeProfile.fromBars(bars, 20, 50, 0.70);
		var b = VolumeProfile.fromBars(bars, 20, 50, 0.70);
		Assert.floatEquals(a.poc, b.poc, 0);
		Assert.floatEquals(a.vaHigh, b.vaHigh, 0);
		Assert.floatEquals(a.vaLow, b.vaLow, 0);
		Assert.floatEquals(a.valueAreaVolFrac, b.valueAreaVolFrac, 0);
	}

	/** Bucket E3 — golden histogram: single-print ladder, heavy bin exact. */
	public function testGoldenHistogramHeavyBin() {
		// Establish [100,106] span with zero-vol edges; place prints at bin midpoints so
		// price→bin is exact (price==winHigh would clamp into the last bin).
		var bars = [bar(100, 100, 100, 100, 0, 0)];
		for (i in 0...6) {
			var px = 100.5 + i; // 100.5..105.5 → bins 0..5 with binWidth=1
			bars.push(bar(px, px, px, px, i == 4 ? 10000.0 : 10.0, i + 1));
		}
		bars.push(bar(106, 106, 106, 106, 0, 7));
		var hist = VolumeProfile.histogram(bars, 8, 6);
		Assert.equals(6, hist.length);
		Assert.floatEquals(10000.0, hist[4], 1e-9);
		for (i in 0...6) if (i != 4) Assert.floatEquals(10.0, hist[i], 1e-9);
		var lv = VolumeProfile.fromBars(bars, 8, 6, 0.70);
		Assert.floatEquals(104.5, lv.poc, 1e-9);
		Assert.isTrue(lv.poc >= lv.vaLow - 1e-9 && lv.poc <= lv.vaHigh + 1e-9);
		Assert.isTrue(lv.valueAreaVolFrac >= 0.70 - 1e-9);
	}

	/** Bucket E3 — bin count change must keep POC near the heavy print. */
	public function testBinSensitivityPocStableNearHeavy() {
		var bars = [for (i in 0...20) {
			var px = 100.0 + (i % 10) * 0.5;
			var vol = (Math.abs(px - 102.5) < 0.01) ? 5000.0 : 50.0;
			bar(px, px + 0.01, px - 0.01, px, vol, i);
		}];
		var poc20 = VolumeProfile.fromBars(bars, 20, 20, 0.70).poc;
		var poc40 = VolumeProfile.fromBars(bars, 20, 40, 0.70).poc;
		var poc80 = VolumeProfile.fromBars(bars, 20, 80, 0.70).poc;
		Assert.isTrue(Math.abs(poc20 - 102.5) < 1.0, 'poc20=$poc20');
		Assert.isTrue(Math.abs(poc40 - 102.5) < 0.75, 'poc40=$poc40');
		Assert.isTrue(Math.abs(poc80 - 102.5) < 0.5, 'poc80=$poc80');
		Assert.isTrue(Math.abs(poc20 - poc80) < 1.5, 'bin shift too large');
	}
}
