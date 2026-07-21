package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.CompositeProfile;
import musescript.indicators.lib.ConcealingBabySwallow;

/**
 * Batch 28: 2 indicators ported from wickra-core (composite_profile,
 * concealing_baby_swallow). The other 3 originally assigned to this batch
 * (crab, cup_and_handle, cypher) were dropped during reconciliation -- they
 * were written against a `PatternSwingHelpers.xabcd`/`ratiosIn` API that was
 * never actually created, leaving them permanently non-compiling. Reinstated
 * as TODO in PORT_INVENTORY.txt rather than shipped broken.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 */
class TestPortBatch28 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── CompositeProfile ─────────────────────────────────────────

	public function testCompositeProfileAccessorsAndMetadata() {
		var p = new CompositeProfile(100, 50, 0.7);
		Assert.equals(100, p.warmupPeriod());
		Assert.equals("CompositeProfile", p.name());
		Assert.isFalse(p.isReady());
	}

	public function testCompositeProfileFirstEmissionAtWarmupPeriod() {
		var p = new CompositeProfile(4, 8, 0.7);
		var out = null;
		for (i in 0...6) {
			var v = p.update(bar(100.0, 110.0, 90.0, 100.0, 1000.0, i));
			if (i < 3) Assert.isNull(v);
			if (i == 3) out = v;
		}
		Assert.notNull(out);
	}

	public function testCompositeProfileValueAreaBracketsPoc() {
		var p = new CompositeProfile(20, 30, 0.7);
		for (i in 0...40) {
			var hi = 110.0 + Math.sin(i * 0.3) * 8.0;
			var lo = 90.0 + Math.cos(i * 0.3) * 8.0;
			var out = p.update(bar((hi + lo) / 2, hi, lo, (hi + lo) / 2, 1000.0, i));
			if (out != null) {
				Assert.isTrue(out.val <= out.poc && out.poc <= out.vah);
			}
		}
	}

	public function testCompositeProfilePocAtHeavyCluster() {
		var p = new CompositeProfile(6, 30, 0.7);
		var out = null;
		for (i in 0...5) out = p.update(bar(100.0, 101.0, 99.0, 100.0, 5000.0, i));
		out = p.update(bar(100.0, 140.0, 60.0, 100.0, 50.0, 5));
		Assert.notNull(out);
		Assert.isTrue(Math.abs(out.poc - 100.0) < 5.0);
	}

	public function testCompositeProfileResetClearsState() {
		var p = new CompositeProfile(4, 8, 0.7);
		for (i in 0...6) p.update(bar(100.0, 110.0, 90.0, 100.0, 1000.0, i));
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isFalse(p.isReady());
		Assert.isNull(p.update(bar(100.0, 110.0, 90.0, 100.0, 1000.0, 0)));
	}

	public function testCompositeProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var hi = 110.0 + Math.sin(i * 0.25) * 9.0;
			bar((hi + 90.0) / 2, hi, 90.0, (hi + 90.0) / 2, 1000.0 + i, i);
		}];
		var a = new CompositeProfile(50, 50, 0.7), b = new CompositeProfile(50, 50, 0.7);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i].poc, streamed[i].poc);
			Assert.floatEquals(batched[i].vah, streamed[i].vah);
			Assert.floatEquals(batched[i].val, streamed[i].val);
		}
	}

	public function testCompositeProfileFlatWindowCollapsesToPrice() {
		var p = new CompositeProfile(2, 4, 0.7);
		p.update(bar(50.0, 50.0, 50.0, 50.0, 10.0, 0));
		var out = p.update(bar(50.0, 50.0, 50.0, 50.0, 10.0, 1));
		Assert.notNull(out);
		Assert.floatEquals(out.poc, out.vah);
		Assert.floatEquals(out.poc, out.val);
	}

	public function testCompositeProfileZeroVolumeWindowIsHandled() {
		var p = new CompositeProfile(2, 4, 0.7);
		p.update(bar(50.0, 60.0, 40.0, 50.0, 0.0, 0));
		Assert.notNull(p.update(bar(50.0, 60.0, 40.0, 50.0, 0.0, 1)));
	}

	// ── ConcealingBabySwallow ─────────────────────────────────────────

	public function testConcealingBabySwallowAccessorsAndMetadata() {
		var t = new ConcealingBabySwallow();
		Assert.equals("ConcealingBabySwallow", t.name());
		Assert.equals(4, t.warmupPeriod());
		Assert.isFalse(t.isReady());
	}

	public function testConcealingBabySwallowIsPlusOne() {
		var t = new ConcealingBabySwallow();
		Assert.floatEquals(0.0, t.update(bar(20.0, 20.1, 14.9, 15.0, 1.0, 0)));
		Assert.floatEquals(0.0, t.update(bar(16.0, 16.1, 11.9, 12.0, 1.0, 1)));
		Assert.floatEquals(0.0, t.update(bar(11.0, 13.0, 9.9, 10.0, 1.0, 2)));
		Assert.floatEquals(1.0, t.update(bar(14.0, 14.1, 8.9, 9.0, 1.0, 3)));
	}

	public function testConcealingBabySwallowFirstBarNotMarubozuYieldsZero() {
		var t = new ConcealingBabySwallow();
		t.update(bar(15.0, 20.1, 14.9, 20.0, 1.0, 0)); // bar1 white
		t.update(bar(16.0, 16.1, 11.9, 12.0, 1.0, 1));
		t.update(bar(11.0, 13.0, 9.9, 10.0, 1.0, 2));
		Assert.floatEquals(0.0, t.update(bar(14.0, 14.1, 8.9, 9.0, 1.0, 3)));
	}

	public function testConcealingBabySwallowThirdBarNoGapYieldsZero() {
		var t = new ConcealingBabySwallow();
		t.update(bar(20.0, 20.1, 14.9, 15.0, 1.0, 0));
		t.update(bar(16.0, 16.1, 11.9, 12.0, 1.0, 1));
		t.update(bar(12.5, 13.0, 9.9, 10.0, 1.0, 2)); // opens at/above bar2 close -> no gap
		Assert.floatEquals(0.0, t.update(bar(14.0, 14.1, 8.9, 9.0, 1.0, 3)));
	}

	public function testConcealingBabySwallowFourthBarNotBlackYieldsZero() {
		var t = new ConcealingBabySwallow();
		t.update(bar(20.0, 20.1, 14.9, 15.0, 1.0, 0));
		t.update(bar(16.0, 16.1, 11.9, 12.0, 1.0, 1));
		t.update(bar(11.0, 13.0, 9.9, 10.0, 1.0, 2));
		Assert.floatEquals(0.0, t.update(bar(9.0, 14.1, 8.9, 14.0, 1.0, 3))); // white bar4
	}

	public function testConcealingBabySwallowBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var hi = 100.0 + Math.sin(i * 0.4) * 6.0;
			var lo = hi - 4.0;
			bar((hi + lo) / 2, hi, lo, (hi + lo) / 2 - 0.5, 1.0, i);
		}];
		var a = new ConcealingBabySwallow(), b = new ConcealingBabySwallow();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
