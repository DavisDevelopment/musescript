package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 12: 10 indicators (high_low_range, gravestone_doji, hammer,
 * hanging_man, harami, harami_cross, heikin_ashi, heikin_ashi_oscillator,
 * fractal_chaos_bands, decycler_oscillator) — standard published formulas
 * (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch12 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── HighLowRange ──────────────────────────────────────────────────────

	public function testHighLowRangeReferenceValue() {
		var h = new HighLowRange();
		Assert.floatEquals(4.0, h.update(bar(10.0, 12.0, 8.0, 11.0, 1.0)));
	}

	// ── GravestoneDoji ────────────────────────────────────────────────────

	public function testGravestoneDojiTrue() {
		var g = new GravestoneDoji();
		Assert.floatEquals(1.0, g.update(bar(10.0, 20.0, 10.0, 10.01, 1.0)));
	}

	public function testGravestoneDojiFalseOnDragonfly() {
		var g = new GravestoneDoji();
		Assert.floatEquals(0.0, g.update(bar(20.0, 20.0, 10.0, 19.9, 1.0)));
	}

	// ── Hammer / HangingMan ───────────────────────────────────────────────

	public function testHammerTrueAfterDowntrend() {
		var h = new Hammer(3);
		h.update(bar(20.0, 20.5, 19.5, 20.0, 1.0));
		h.update(bar(19.0, 19.5, 17.0, 17.5, 1.0));
		h.update(bar(17.0, 17.2, 14.0, 14.5, 1.0));
		// hammer shape: small body near top, long lower shadow, undercuts context lows.
		var out = h.update(bar(13.0, 13.2, 8.0, 13.1, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	public function testHangingManTrueAfterUptrend() {
		var hm = new HangingMan(3);
		hm.update(bar(10.0, 10.5, 9.5, 10.0, 1.0));
		hm.update(bar(11.0, 11.5, 10.5, 11.2, 1.0));
		hm.update(bar(12.0, 12.5, 11.5, 12.3, 1.0));
		// same hammer-shape bar (small body near top, long LOWER shadow, negligible
		// upper shadow) but now the context is an UPtrend -> hanging man.
		var out = hm.update(bar(14.0, 14.2, 8.0, 14.1, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── Harami / HaramiCross ──────────────────────────────────────────────

	public function testHaramiBullish() {
		var h = new Harami();
		h.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1: open 12, close 9
		var out = h.update(bar(10.0, 10.8, 9.5, 10.5, 1.0)); // green bar2, body [10,10.5] inside [9,12]
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	public function testHaramiCrossBullish() {
		var h = new HaramiCross();
		h.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1: open 12, close 9
		var out = h.update(bar(10.5, 10.6, 10.4, 10.505, 1.0)); // doji bar2, body inside [9,12]
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── HeikinAshi / HeikinAshiOscillator ─────────────────────────────────

	public function testHeikinAshiFirstBarReferenceValue() {
		var ha = new HeikinAshi();
		var out = ha.update(bar(10.0, 14.0, 8.0, 12.0, 1.0));
		Assert.notNull(out);
		// haClose = (10+14+8+12)/4 = 11; haOpen = (10+12)/2 = 11 (first bar).
		Assert.floatEquals(11.0, out.close, 1e-9);
		Assert.floatEquals(11.0, out.open, 1e-9);
	}

	public function testHeikinAshiOscillatorSignMatchesTrend() {
		var hao = new HeikinAshiOscillator();
		var out = null;
		for (i in 0...10) out = hao.update(bar(100.0 + i, 101.0 + i, 99.0 + i, 100.8 + i, 1.0));
		Assert.notNull(out);
		Assert.isTrue(out > 0.0); // steadily green synthetic candles in an uptrend
	}

	// ── FractalChaosBands ─────────────────────────────────────────────────

	public function testFractalChaosBandsDetectsFractalHigh() {
		var fcb = new FractalChaosBands();
		var bars = [
			bar(10.0, 11.0, 10.0, 10.5, 1.0),
			bar(10.0, 12.0, 9.5, 10.5, 1.0),
			bar(10.0, 15.0, 8.0, 10.5, 1.0), // fractal high AND low candidate (index 2)
			bar(10.0, 13.0, 9.0, 10.5, 1.0),
			bar(10.0, 12.0, 9.5, 10.5, 1.0) // 5th bar confirms both fractals
		];
		var out = null;
		for (b in bars) out = fcb.update(b);
		Assert.notNull(out);
		Assert.floatEquals(15.0, out.upper, 1e-9);
		Assert.floatEquals(8.0, out.lower, 1e-9);
	}

	// ── DecyclerOscillator ────────────────────────────────────────────────

	public function testDecyclerOscillatorZeroOnFlatSeries() {
		var d = new DecyclerOscillator(10, 30);
		var out = null;
		for (i in 0...15) out = d.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testDecyclerOscillatorBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.2) * 6.0];
		var a = new DecyclerOscillator(10, 30), b = new DecyclerOscillator(10, 30);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
