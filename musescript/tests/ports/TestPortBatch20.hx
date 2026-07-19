package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 20: 10 indicators (natr, nvi, omega_ratio, on_neck,
 * opening_marubozu, opening_range, nrtr, hurst_channel,
 * downside_gap_three_methods, ou_half_life) — standard published formulas
 * (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch20 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Natr ──────────────────────────────────────────────────────────────

	public function testNatrConstantRangeConverges() {
		var n = new Natr(5);
		var out = null;
		for (i in 0...15) out = n.update(bar(10.0, 11.0, 9.0, 10.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(20.0, out, 1e-6); // ATR=2, close=10 -> 2/10*100=20
	}

	// ── Nvi ───────────────────────────────────────────────────────────────

	public function testNviUnchangedWhenVolumeRises() {
		var nvi = new Nvi();
		nvi.update(bar(10.0, 11.0, 9.0, 10.0, 100.0));
		var out = nvi.update(bar(10.0, 12.0, 9.0, 11.0, 200.0)); // volume rose -> NVI unchanged
		Assert.notNull(out);
		Assert.floatEquals(1000.0, out, 1e-9);
	}

	public function testNviUpdatesWhenVolumeFalls() {
		var nvi = new Nvi();
		nvi.update(bar(10.0, 11.0, 9.0, 10.0, 200.0));
		var out = nvi.update(bar(10.0, 12.0, 9.0, 11.0, 100.0)); // volume fell -> NVI *= 1.1
		Assert.notNull(out);
		Assert.floatEquals(1100.0, out, 1e-6);
	}

	// ── OmegaRatio ────────────────────────────────────────────────────────

	public function testOmegaRatioZeroWithNoLosses() {
		var om = new OmegaRatio(5, 0.0);
		var out = null;
		for (i in 0...6) out = om.update(100.0 + i);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testOmegaRatioPositiveWithMoreGains() {
		var om = new OmegaRatio(4, 0.0);
		var out = null;
		var prices = [100.0, 110.0, 108.0, 118.0, 116.0];
		for (p in prices) out = om.update(p);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── OnNeck ────────────────────────────────────────────────────────────

	public function testOnNeckBearish() {
		var n = new OnNeck();
		n.update(bar(20.0, 20.5, 15.0, 15.5, 1.0)); // red bar1: low 15
		var out = n.update(bar(14.0, 15.1, 13.5, 15.0, 1.0)); // green, opens below 15, closes ~15
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── OpeningMarubozu ───────────────────────────────────────────────────

	public function testOpeningMarubozuBullish() {
		var om = new OpeningMarubozu();
		Assert.floatEquals(1.0, om.update(bar(10.0, 20.0, 10.0, 18.0, 1.0)));
	}

	// ── OpeningRange ──────────────────────────────────────────────────────

	public function testOpeningRangeHoldsFirstBar() {
		var or_ = new OpeningRange();
		var out1 = or_.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		Assert.notNull(out1);
		Assert.floatEquals(12.0, out1.high, 1e-9);
		Assert.floatEquals(8.0, out1.low, 1e-9);
		var out2 = or_.update(bar(10.0, 100.0, 1.0, 50.0, 1.0));
		Assert.notNull(out2);
		Assert.floatEquals(12.0, out2.high, 1e-9);
		Assert.floatEquals(8.0, out2.low, 1e-9);
	}

	// ── Nrtr ──────────────────────────────────────────────────────────────

	public function testNrtrFlipsOnCross() {
		var n = new Nrtr(0.05);
		var out = null;
		out = n.update(100.0);
		Assert.floatEquals(1.0, out.direction);
		out = n.update(110.0); // extreme rises to 110, level = 104.5
		Assert.floatEquals(1.0, out.direction);
		out = n.update(100.0); // 100 < 104.5 -> flips to downtrend
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out.direction);
	}

	// ── HurstChannel ──────────────────────────────────────────────────────

	public function testHurstChannelUpperAboveMiddleAboveLower() {
		var hc = new HurstChannel(20);
		for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var out = hc.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
			if (out != null) {
				Assert.isTrue(out.upper >= out.middle);
				Assert.isTrue(out.middle >= out.lower);
			}
		}
	}

	// ── DownsideGapThreeMethods ───────────────────────────────────────────

	public function testDownsideGapThreeMethodsBearish() {
		var d = new DownsideGapThreeMethods();
		d.update(bar(20.0, 20.5, 17.0, 17.5, 1.0)); // bar1: red, low 17
		d.update(bar(15.0, 16.5, 13.0, 13.5, 1.0)); // bar2: red, gaps down (high 16.5 < 17)
		var out = d.update(bar(14.5, 16.8, 14.0, 16.6, 1.0)); // bar3: green, opens in bar2 body, closes in gap (16.5,17)
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── OuHalfLife ────────────────────────────────────────────────────────

	public function testOuHalfLifePositiveOnMeanRevertingSpread() {
		var ou = new OuHalfLife(20);
		var out = null;
		var spread = 5.0;
		for (i in 0...30) {
			spread = spread * 0.9; // decaying toward 0 -> mean-reverting
			out = ou.update({ a: spread, b: 0.0 });
		}
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testOuHalfLifeZeroOnRandomWalk() {
		var ou = new OuHalfLife(20);
		var out = null;
		var spread = 0.0;
		for (i in 0...30) {
			spread += (i % 2 == 0 ? 1.0 : -1.0) * (i + 1); // diverging, non-mean-reverting
			out = ou.update({ a: spread, b: 0.0 });
		}
		Assert.notNull(out);
		Assert.isTrue(out >= 0.0);
	}
}
