package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 05: 10 indicators (bipower_variation, body_size_pct, beta,
 * beta_neutral_spread, better_volume, belt_hold, bollinger,
 * bollinger_bandwidth, burke_ratio, camarilla_pivots) implemented directly
 * against their standard published formulas (no local Wickra source clone
 * to transcribe from — see PORTING.md note). Known-value cases are derived
 * by hand from those formulas; batch_equals_streaming still holds.
 */
class TestPortBatch05 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── BodySizePct ───────────────────────────────────────────────────────

	public function testBodySizePctFullBodyIsHundred() {
		var b = new BodySizePct();
		Assert.floatEquals(100.0, b.update(bar(10.0, 12.0, 10.0, 12.0, 1.0)));
	}

	public function testBodySizePctReferenceValue() {
		// body = |12-10| = 2, range = 14-8 = 6 -> 2/6*100 = 33.333...
		var b = new BodySizePct();
		Assert.floatEquals(33.333333, b.update(bar(10.0, 14.0, 8.0, 12.0, 1.0)), 1e-4);
	}

	public function testBodySizePctZeroRangeIsZero() {
		var b = new BodySizePct();
		Assert.floatEquals(0.0, b.update(bar(10.0, 10.0, 10.0, 10.0, 1.0)));
	}

	// ── BeltHold ──────────────────────────────────────────────────────────

	public function testBeltHoldBullish() {
		// open == low, close == high, full-body bar -> +1.
		var b = new BeltHold();
		Assert.floatEquals(1.0, b.update(bar(10.0, 20.0, 10.0, 20.0, 1.0)));
	}

	public function testBeltHoldBearish() {
		var b = new BeltHold();
		Assert.floatEquals(-1.0, b.update(bar(20.0, 20.0, 10.0, 10.0, 1.0)));
	}

	public function testBeltHoldSmallBodyIsZero() {
		var b = new BeltHold();
		Assert.floatEquals(0.0, b.update(bar(14.9, 20.0, 10.0, 15.0, 1.0)));
	}

	// ── Beta / BetaNeutralSpread ─────────────────────────────────────────

	public function testBetaPerfectCoMovementIsOne() {
		var b = new Beta(10);
		var out = null;
		for (i in 1...12) out = b.update({ a: i * 0.01, b: i * 0.01 });
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	public function testBetaDoubleSensitivityIsTwo() {
		var b = new Beta(10);
		var out = null;
		for (i in 1...12) out = b.update({ a: 2.0 * i * 0.01, b: i * 0.01 });
		Assert.notNull(out);
		Assert.floatEquals(2.0, out, 1e-6);
	}

	public function testBetaNeutralSpreadZeroWhenPerfectlyHedged() {
		// asset == 2*bench, beta == 2, so spread = a - 2*b = 0 exactly.
		var s = new BetaNeutralSpread(10);
		var out = null;
		for (i in 1...12) out = s.update({ a: 2.0 * i * 0.01, b: i * 0.01 });
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testBetaBatchEqualsStreaming() {
		var inputs:Array<musescript.indicators.lib.Beta.BetaPair> = [for (i in 0...50) { a: Math.sin(i * 0.2) * 0.01, b: Math.sin(i * 0.2 + 0.3) * 0.01 }];
		var a1 = new Beta(10), a2 = new Beta(10);
		var batched = IndicatorBatch.run(a1, inputs);
		var streamed = [for (x in inputs) a2.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── BetterVolume ──────────────────────────────────────────────────────

	public function testBetterVolumeConstantVolumeIsOne() {
		var b = new BetterVolume(5);
		var out = null;
		for (i in 0...10) out = b.update(bar(10.0, 10.0, 10.0, 10.0, 500.0));
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-9);
	}

	public function testBetterVolumeSpikeAboveOne() {
		var b = new BetterVolume(5);
		for (i in 0...5) b.update(bar(10.0, 10.0, 10.0, 10.0, 100.0));
		var out = b.update(bar(10.0, 10.0, 10.0, 10.0, 1000.0));
		Assert.notNull(out);
		Assert.isTrue(out > 1.0);
	}

	// ── Bollinger / BollingerBandwidth ───────────────────────────────────

	public function testBollingerFlatSeriesCollapsesBands() {
		var b = new Bollinger(5, 2.0);
		var out = null;
		for (i in 0...10) out = b.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out.upper, 1e-9);
		Assert.floatEquals(50.0, out.middle, 1e-9);
		Assert.floatEquals(50.0, out.lower, 1e-9);
	}

	public function testBollingerUpperAboveMiddleAboveLower() {
		var b = new Bollinger(10, 2.0);
		for (i in 0...30) {
			var out = b.update(100.0 + Math.sin(i * 0.4) * 5.0);
			if (out != null) {
				Assert.isTrue(out.upper >= out.middle);
				Assert.isTrue(out.middle >= out.lower);
			}
		}
	}

	public function testBollingerBandwidthNonNegative() {
		var bw = new BollingerBandwidth(10, 2.0);
		for (i in 0...30) {
			var out = bw.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	public function testBollingerBatchEqualsStreaming() {
		var prices = [for (i in 0...40) 100.0 + Math.sin(i * 0.25) * 6.0];
		var a = new Bollinger(10, 2.0), b = new Bollinger(10, 2.0);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) { Assert.isNull(streamed[i]); continue; }
			Assert.floatEquals(batched[i].upper, streamed[i].upper, 1e-9);
			Assert.floatEquals(batched[i].middle, streamed[i].middle, 1e-9);
			Assert.floatEquals(batched[i].lower, streamed[i].lower, 1e-9);
		}
	}

	// ── BipowerVariation ──────────────────────────────────────────────────

	public function testBipowerVariationConstantPriceIsZero() {
		var bv = new BipowerVariation(5);
		var out = null;
		for (i in 0...10) out = bv.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testBipowerVariationNonNegative() {
		var bv = new BipowerVariation(10);
		for (i in 0...40) {
			var out = bv.update(100.0 + Math.sin(i * 0.5) * 10.0 + (i % 7 == 0 ? 5.0 : 0.0));
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	public function testBipowerVariationBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = new BipowerVariation(10), b = new BipowerVariation(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── BurkeRatio ────────────────────────────────────────────────────────

	public function testBurkeRatioNoDrawdownIsZero() {
		var equity = [for (i in 1...21) 100.0 + i];
		var br = new BurkeRatio(20);
		var out = null;
		for (e in equity) out = br.update(e);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testBurkeRatioPositiveWithRecoveredDrawdown() {
		var equity = [100.0, 110.0, 90.0, 120.0, 130.0];
		var br = new BurkeRatio(5);
		var out = null;
		for (e in equity) out = br.update(e);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── CamarillaPivots ───────────────────────────────────────────────────

	public function testCamarillaPivotsFirstBarIsNull() {
		var cp = new CamarillaPivots();
		Assert.isNull(cp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0)));
	}

	public function testCamarillaPivotsReferenceValues() {
		// prev bar: high=12, low=8 (range=4), close=11. Levels lag by one bar.
		var cp = new CamarillaPivots();
		cp.update(bar(10.0, 12.0, 8.0, 11.0, 1.0));
		var out = cp.update(bar(11.0, 13.0, 10.0, 12.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(11.0 + 4.0 * 1.1 / 2.0, out.r4, 1e-9);
		Assert.floatEquals(11.0 - 4.0 * 1.1 / 2.0, out.s4, 1e-9);
		Assert.floatEquals((12.0 + 8.0 + 11.0) / 3.0, out.pivot, 1e-9);
		// R/S ladders are centered on close (not the H/L/C pivot), so each ladder
		// is independently monotonic but need not interleave with `pivot` itself.
		Assert.isTrue(out.r4 > out.r3 && out.r3 > out.r2 && out.r2 > out.r1 && out.r1 > 11.0);
		Assert.isTrue(11.0 > out.s1 && out.s1 > out.s2 && out.s2 > out.s3 && out.s3 > out.s4);
	}

	// ── BetaNeutralSpread / BetterVolume / registration safety net covered
	// by TestIndicatorPorts.testEveryRegisteredIndicatorIsCallable.
}
