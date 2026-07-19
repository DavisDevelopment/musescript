package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 19: 10 indicators (median_ma, median_price, mid_point, mid_price,
 * minus_dm, minus_di, modified_ma_stop, morning_doji_star,
 * morning_evening_star, cybernetic_cycle) — standard published formulas
 * (see PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch19 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── MedianMa / MedianPrice ────────────────────────────────────────────

	public function testMedianMaReferenceValue() {
		var mm = new MedianMa(5);
		var out = null;
		for (p in [1.0, 2.0, 3.0, 4.0, 5.0]) out = mm.update(p);
		Assert.notNull(out);
		Assert.floatEquals(3.0, out, 1e-9);
	}

	public function testMedianPriceReferenceValue() {
		var mp = new MedianPrice();
		Assert.floatEquals(11.0, mp.update(bar(10.0, 14.0, 8.0, 12.0, 1.0)));
	}

	// ── MidPoint / MidPrice ───────────────────────────────────────────────

	public function testMidPointReferenceValue() {
		var mp = new MidPoint(3);
		var out = null;
		for (p in [10.0, 15.0, 5.0]) out = mp.update(p);
		Assert.notNull(out);
		Assert.floatEquals(10.0, out, 1e-9); // (15+5)/2
	}

	public function testMidPriceReferenceValue() {
		var mp = new MidPrice(3);
		var out = null;
		out = mp.update(bar(10.0, 12.0, 9.0, 11.0, 1.0));
		out = mp.update(bar(10.0, 15.0, 8.0, 11.0, 1.0));
		out = mp.update(bar(10.0, 11.0, 7.0, 11.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals((15.0 + 7.0) / 2.0, out, 1e-9);
	}

	// ── MinusDm / MinusDi ─────────────────────────────────────────────────

	public function testMinusDmZeroOnPureUptrend() {
		var mdm = new MinusDm(5);
		var out = null;
		for (i in 0...20) out = mdm.update(bar(100.0 + i * 2.0, 101.0 + i * 2.0, 99.0 + i * 2.0, 100.5 + i * 2.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testMinusDiZeroTrueRangeYieldsZero() {
		var mdi = new MinusDi(5);
		var out = null;
		for (i in 0...20) out = mdi.update(bar(10.0, 10.0, 10.0, 10.0, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testMinusDiPositiveOnPureDowntrend() {
		var mdi = new MinusDi(14);
		var out = null;
		for (i in 0...30) {
			var base = 100.0 - i * 2.0;
			out = mdi.update(bar(base + 1.0, base + 1.5, base - 0.5, base, 1.0));
		}
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	// ── ModifiedMaStop ────────────────────────────────────────────────────

	public function testModifiedMaStopNeverDecreases() {
		var mms = new ModifiedMaStop(10, 5, 2.0);
		var last:Null<Float> = null;
		for (i in 0...40) {
			var base = 100.0 + i;
			var out = mms.update(bar(base, base + 1.0, base - 1.0, base, 1.0));
			if (out != null) {
				if (last != null) Assert.isTrue(out >= last - 1e-9);
				last = out;
			}
		}
		Assert.notNull(last);
	}

	// ── MorningDojiStar ───────────────────────────────────────────────────

	public function testMorningDojiStarBullish() {
		var m = new MorningDojiStar();
		m.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1, close 9
		m.update(bar(8.5, 8.6, 8.4, 8.505, 1.0)); // gapped-down doji (high 8.6 < 9)
		var out = m.update(bar(9.0, 12.0, 8.9, 11.5, 1.0)); // gaps up (low 8.9 > 8.6), closes above bar1 mid (10.5)
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── MorningEveningStar ────────────────────────────────────────────────

	public function testMorningEveningStarBullish() {
		var m = new MorningEveningStar();
		m.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1, body 3, close 9
		m.update(bar(8.5, 8.7, 8.3, 8.6, 1.0)); // star bar2, small body 0.1, gaps down (high 8.7<9)
		var out = m.update(bar(9.0, 12.0, 8.9, 11.5, 1.0)); // green bar3, closes above bar1 mid (10.5)
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	public function testMorningEveningStarBearish() {
		var m = new MorningEveningStar();
		m.update(bar(9.0, 12.0, 8.5, 12.0, 1.0)); // green bar1, body 3, close 12
		m.update(bar(12.5, 12.7, 12.3, 12.6, 1.0)); // star bar2, small body, gaps up (low 12.3>12)
		var out = m.update(bar(12.0, 12.1, 9.0, 9.5, 1.0)); // red bar3, closes below bar1 mid (10.5)
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── CyberneticCycle ───────────────────────────────────────────────────

	public function testCyberneticCycleZeroOnFlatSeries() {
		var cc = new CyberneticCycle(0.07);
		var out = null;
		for (i in 0...20) out = cc.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testCyberneticCycleBatchEqualsStreaming() {
		var prices = [for (i in 0...50) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new CyberneticCycle(0.07), b = new CyberneticCycle(0.07);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
