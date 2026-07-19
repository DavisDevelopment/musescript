package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 17: 10 indicators (linreg_slope, linreg_intercept, log_return,
 * long_legged_doji, long_line, ma_envelope, macd_histogram, macd_ext,
 * macd_fix, kicking_by_length) — standard published formulas (see
 * PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch17 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── LinRegSlope / LinRegIntercept ─────────────────────────────────────

	public function testLinRegSlopeZeroOnFlatSeries() {
		var ls = new LinRegSlope(10);
		var out = null;
		for (i in 0...15) out = ls.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testLinRegSlopeMatchesKnownLine() {
		// y = 3x + 5 for x=0..9 -> slope should be exactly 3.
		var ls = new LinRegSlope(10);
		var out = null;
		for (i in 0...10) out = ls.update(3.0 * i + 5.0);
		Assert.notNull(out);
		Assert.floatEquals(3.0, out, 1e-6);
	}

	public function testLinRegInterceptMatchesKnownLine() {
		var li = new LinRegIntercept(10);
		var out = null;
		for (i in 0...10) out = li.update(3.0 * i + 5.0);
		Assert.notNull(out);
		Assert.floatEquals(5.0, out, 1e-6);
	}

	// ── LogReturn ─────────────────────────────────────────────────────────

	public function testLogReturnZeroOnFlatPrice() {
		var lr = new LogReturn();
		lr.update(100.0);
		var out = lr.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testLogReturnReferenceValue() {
		var lr = new LogReturn();
		lr.update(100.0);
		var out = lr.update(110.0);
		Assert.notNull(out);
		Assert.floatEquals(Math.log(1.1), out, 1e-9);
	}

	// ── LongLeggedDoji ────────────────────────────────────────────────────

	public function testLongLeggedDojiTrue() {
		var lld = new LongLeggedDoji();
		Assert.floatEquals(1.0, lld.update(bar(15.0, 20.0, 10.0, 15.005, 1.0)));
	}

	public function testLongLeggedDojiFalseOnLopsidedShadows() {
		// dragonfly-shaped (negligible upper) -> not long-legged (needs both sides).
		var lld = new LongLeggedDoji();
		Assert.floatEquals(0.0, lld.update(bar(20.0, 20.0, 10.0, 19.99, 1.0)));
	}

	// ── LongLine ──────────────────────────────────────────────────────────

	public function testLongLineDetectsOversizedGreenBody() {
		var ll = new LongLine(5, 1.5);
		for (i in 0...5) ll.update(bar(10.0, 11.0, 9.0, 10.5, 1.0)); // avg body ~0.5
		var out = ll.update(bar(10.0, 20.0, 9.5, 19.0, 1.0)); // body 9 >> 1.5*0.5
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── MaEnvelope ────────────────────────────────────────────────────────

	public function testMaEnvelopeReferenceValues() {
		var me = new MaEnvelope(5, 0.02);
		var out = null;
		for (i in 0...10) out = me.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(100.0, out.middle, 1e-9);
		Assert.floatEquals(102.0, out.upper, 1e-9);
		Assert.floatEquals(98.0, out.lower, 1e-9);
	}

	// ── MacdHistogram / MacdExt / MacdFix ────────────────────────────────

	public function testMacdHistogramZeroOnFlatSeries() {
		var mh = new MacdHistogram(12, 26, 9);
		var out = null;
		for (i in 0...60) out = mh.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-6);
	}

	public function testMacdExtHistogramMatchesMacdMinusSignal() {
		var me = new MacdExt(12, 26, 9);
		var out = null;
		for (i in 0...60) out = me.update(100.0 + Math.sin(i * 0.2) * 5.0);
		Assert.notNull(out);
		Assert.floatEquals(out.macd - out.signal, out.histogram, 1e-9);
	}

	public function testMacdFixMatchesMacdExtWithFixedPeriods() {
		var mf = new MacdFix(9);
		var me = new MacdExt(12, 26, 9);
		var out1 = null, out2 = null;
		for (i in 0...60) {
			var p = 100.0 + Math.sin(i * 0.25) * 5.0;
			out1 = mf.update(p);
			out2 = me.update(p);
		}
		Assert.notNull(out1);
		Assert.notNull(out2);
		Assert.floatEquals(out2.histogram, out1.histogram, 1e-9);
	}

	// ── KickingByLength ───────────────────────────────────────────────────

	public function testKickingByLengthRequiresLongerSecondBar() {
		var kbl = new KickingByLength();
		kbl.update(bar(20.0, 20.1, 10.0, 10.05, 1.0)); // red marubozu, range 10.1
		// green marubozu, gaps up, but SHORTER range than bar1 -> should NOT fire.
		var out = kbl.update(bar(21.0, 25.9, 20.95, 25.85, 1.0));
		Assert.notNull(out);
		Assert.floatEquals(0.0, out);
	}

	public function testKickingByLengthFiresWhenSecondBarLonger() {
		var kbl = new KickingByLength();
		kbl.update(bar(20.0, 20.1, 10.0, 10.05, 1.0)); // red marubozu, range 10.1
		var out = kbl.update(bar(21.0, 40.9, 20.95, 40.85, 1.0)); // green marubozu, gaps up, LONGER range
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}
}
