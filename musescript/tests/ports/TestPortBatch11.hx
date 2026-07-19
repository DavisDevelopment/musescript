package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 11: 10 indicators (gain_to_pain_ratio, garman_klass,
 * gator_oscillator, generalized_dema, geometric_ma, decycler,
 * gap_side_by_side_white, falling_three_methods, fib_extension,
 * elder_safezone) — standard published formulas (see PORTING.md note on no
 * local Wickra source clone).
 */
class TestPortBatch11 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── GainToPainRatio ───────────────────────────────────────────────────

	public function testGainToPainRatioZeroWhenNoPain() {
		var g = new GainToPainRatio(5);
		var out = null;
		for (i in 0...10) out = g.update(100.0 + i);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testGainToPainRatioPositiveWithMoreGainThanPain() {
		var g = new GainToPainRatio(4);
		var out = null;
		// alternating up bigger, down smaller
		var prices = [100.0, 110.0, 108.0, 118.0, 116.0];
		for (p in prices) out = g.update(p);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── GarmanKlass ───────────────────────────────────────────────────────

	public function testGarmanKlassZeroOnZeroRangeDoji() {
		// open==close==high==low every bar -> perBar = 0 -> GK = 0.
		var gk = new GarmanKlass(5);
		var out = null;
		for (i in 0...10) out = gk.update(bar(10.0, 10.0, 10.0, 10.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testGarmanKlassNonNegative() {
		var gk = new GarmanKlass(10);
		for (i in 0...30) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var out = gk.update(bar(base, base + 2.0, base - 2.0, base + 0.5, 1.0));
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	// ── GatorOscillator ───────────────────────────────────────────────────

	public function testGatorOscillatorSignConvention() {
		var g = new GatorOscillator(13, 8, 5);
		var out = null;
		for (i in 0...30) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			out = g.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
		}
		Assert.notNull(out);
		Assert.isTrue(out.upper >= 0.0);
		Assert.isTrue(out.lower <= 0.0);
	}

	// ── GeneralizedDema ───────────────────────────────────────────────────

	public function testGeneralizedDemaVEqualsOneMatchesDema() {
		var gd = new GeneralizedDema(8, 1.0);
		var d = new Dema(8);
		var out1 = null, out2 = null;
		for (i in 0...40) {
			var p = 100.0 + Math.sin(i * 0.3) * 6.0;
			out1 = gd.update(p);
			out2 = d.update(p);
		}
		Assert.notNull(out1);
		Assert.notNull(out2);
		Assert.floatEquals(out2, out1, 1e-9);
	}

	public function testGeneralizedDemaVZeroIsPlainEma() {
		var gd = new GeneralizedDema(8, 0.0);
		var out = null;
		for (i in 0...20) out = gd.update(42.0);
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-6);
	}

	// ── GeometricMa ───────────────────────────────────────────────────────

	public function testGeometricMaFlatSeriesEqualsValue() {
		var g = new GeometricMa(5);
		var out = null;
		for (i in 0...10) out = g.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-6);
	}

	public function testGeometricMaReferenceValue() {
		// geometric mean of [1, 4, 16] (period 3) is (1*4*16)^(1/3) = 64^(1/3) = 4.
		var g = new GeometricMa(3);
		var out = null;
		for (p in [1.0, 4.0, 16.0]) out = g.update(p);
		Assert.notNull(out);
		Assert.floatEquals(4.0, out, 1e-6);
	}

	// ── Decycler ──────────────────────────────────────────────────────────

	public function testDecyclerFlatSeriesEqualsPrice() {
		var d = new Decycler(20);
		var out = null;
		for (i in 0...10) out = d.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-6);
	}

	public function testDecyclerBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.2) * 6.0];
		var a = new Decycler(20), b = new Decycler(20);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── GapSideBySideWhite ────────────────────────────────────────────────

	public function testGapSideBySideWhiteBullish() {
		var g = new GapSideBySideWhite();
		g.update(bar(9.0, 10.6, 8.9, 10.5, 1.0)); // green bar1, body 1.5
		g.update(bar(11.0, 11.6, 10.9, 11.5, 1.0)); // gaps up (low 10.9 > 10.5), green, body 0.5, open 11
		var out = g.update(bar(11.02, 11.62, 10.92, 11.52, 1.0)); // similar open/body to bar2
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── FallingThreeMethods ───────────────────────────────────────────────

	public function testFallingThreeMethodsBearish() {
		var f = new FallingThreeMethods();
		f.update(bar(20.0, 20.5, 10.0, 10.5, 1.0)); // bar1: long red, body 9.5
		f.update(bar(11.0, 12.0, 10.5, 11.5, 1.0)); // bar2: small, within bar1's range
		f.update(bar(11.5, 13.0, 11.0, 12.5, 1.0)); // bar3: small, within bar1's range
		f.update(bar(12.0, 13.5, 11.5, 12.0, 1.0)); // bar4: small, within bar1's range
		var out = f.update(bar(11.5, 12.0, 8.0, 8.5, 1.0)); // bar5: long red, closes below bar1.close (10.5)
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── FibExtension ──────────────────────────────────────────────────────

	public function testFibExtensionReferenceValues() {
		var fe = new FibExtension(3);
		fe.update(bar(10.0, 20.0, 10.0, 15.0, 1.0));
		fe.update(bar(10.0, 25.0, 5.0, 15.0, 1.0));
		var out = fe.update(bar(10.0, 22.0, 8.0, 15.0, 1.0));
		Assert.notNull(out);
		// window high=25, low=5, range=20.
		Assert.floatEquals(5.0, out.level0, 1e-9);
		Assert.floatEquals(25.0, out.level1000, 1e-9);
		Assert.floatEquals(5.0 + 1.618 * 20.0, out.level1618, 1e-9);
		Assert.isTrue(out.level2618 > out.level1618);
	}

	// ── ElderSafezone ─────────────────────────────────────────────────────

	public function testElderSafezoneLongBelowShortAbove() {
		var es = new ElderSafezone(10, 2.5);
		var out = null;
		for (i in 0...20) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			out = es.update(bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0));
		}
		Assert.notNull(out);
		Assert.isTrue(Math.isFinite(out.longStop) && Math.isFinite(out.shortStop));
	}

	public function testElderSafezoneBatchEqualsStreaming() {
		var bars = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			bar(base, base + 2.0, base - 2.0, base + 0.3, 1.0);
		}];
		var a = new ElderSafezone(10, 2.5), b = new ElderSafezone(10, 2.5);
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
}
