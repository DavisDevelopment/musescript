package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;

/**
 * Batch 09: 10 indicators (engulfing, doji_star, counterattack, elder_ray,
 * double_bollinger, drawdown_duration, evwma, ewma_volatility, expectancy,
 * correlation_trend_indicator) — standard published formulas (see
 * PORTING.md note on no local Wickra source clone).
 */
class TestPortBatch09 extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	// ── Engulfing ─────────────────────────────────────────────────────────

	public function testEngulfingBullish() {
		var e = new Engulfing();
		e.update(bar(10.0, 10.5, 8.0, 9.0, 1.0)); // red bar1: open 10, close 9
		var out = e.update(bar(8.5, 11.0, 8.0, 10.5, 1.0)); // green bar2 engulfs bar1's body
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	public function testEngulfingBearish() {
		var e = new Engulfing();
		e.update(bar(9.0, 10.5, 8.5, 10.0, 1.0)); // green bar1: open 9, close 10
		var out = e.update(bar(10.5, 11.0, 8.0, 8.5, 1.0)); // red bar2 engulfs bar1's body
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out);
	}

	// ── DojiStar ──────────────────────────────────────────────────────────

	public function testDojiStarBullish() {
		var d = new DojiStar();
		d.update(bar(12.0, 12.5, 9.0, 10.0, 1.0)); // red bar1, close 10
		var out = d.update(bar(9.5, 9.6, 9.4, 9.505, 1.0)); // gapped-down doji (high 9.6 < 10, body << range)
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── Counterattack ─────────────────────────────────────────────────────

	public function testCounterattackBullish() {
		var c = new Counterattack();
		c.update(bar(12.0, 12.5, 9.0, 9.0, 1.0)); // red bar1, close 9
		var out = c.update(bar(8.0, 9.1, 7.5, 9.0, 1.0)); // gaps down, green, closes at ~9
		Assert.notNull(out);
		Assert.floatEquals(1.0, out);
	}

	// ── ElderRay ──────────────────────────────────────────────────────────

	public function testElderRaySignsMatchExtremesVsEma() {
		var er = new ElderRay(5);
		var out = null;
		for (i in 0...10) out = er.update(bar(10.0, 12.0, 8.0, 10.0, 1.0));
		Assert.notNull(out);
		// Flat series -> ema converges to 10 -> bull = 12-10=2, bear = 8-10=-2.
		Assert.floatEquals(2.0, out.bull, 1e-6);
		Assert.floatEquals(-2.0, out.bear, 1e-6);
	}

	// ── DoubleBollinger ───────────────────────────────────────────────────

	public function testDoubleBollingerNestedOrdering() {
		var db = new DoubleBollinger(10, 1.0, 2.0);
		for (i in 0...30) {
			var out = db.update(100.0 + Math.sin(i * 0.3) * 5.0);
			if (out != null) {
				Assert.isTrue(out.upper2 >= out.upper1);
				Assert.isTrue(out.upper1 >= out.middle);
				Assert.isTrue(out.middle >= out.lower1);
				Assert.isTrue(out.lower1 >= out.lower2);
			}
		}
	}

	public function testDoubleBollingerFlatSeriesCollapses() {
		var db = new DoubleBollinger(5, 1.0, 2.0);
		var out = null;
		for (i in 0...10) out = db.update(50.0);
		Assert.notNull(out);
		Assert.floatEquals(50.0, out.upper2, 1e-9);
		Assert.floatEquals(50.0, out.lower2, 1e-9);
	}

	// ── DrawdownDuration ──────────────────────────────────────────────────

	public function testDrawdownDurationZeroOnNewPeaks() {
		var d = new DrawdownDuration();
		var out = null;
		for (p in [100.0, 101.0, 102.0, 103.0]) out = d.update(p);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out);
	}

	public function testDrawdownDurationCountsBarsBelowPeak() {
		var d = new DrawdownDuration();
		d.update(100.0);
		d.update(90.0); // 1 bar below peak
		d.update(95.0); // 2 bars below peak
		var out = d.update(80.0); // 3 bars below peak
		Assert.notNull(out);
		Assert.floatEquals(3.0, out);
	}

	// ── Evwma ─────────────────────────────────────────────────────────────

	public function testEvwmaFlatSeriesConvergesToConstant() {
		var e = new Evwma(5);
		var out = null;
		for (i in 0...20) out = e.update(bar(42.0, 42.0, 42.0, 42.0, 100.0));
		Assert.notNull(out);
		Assert.floatEquals(42.0, out, 1e-6);
	}

	public function testEvwmaBatchEqualsStreaming() {
		var bars = [for (i in 0...50) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(base, base + 1.0, base - 1.0, base + 0.2, 10.0 + (i % 7) * 5.0);
		}];
		var a = new Evwma(10), b = new Evwma(10);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── EwmaVolatility ────────────────────────────────────────────────────

	public function testEwmaVolatilityZeroOnConstantPrice() {
		var e = new EwmaVolatility(0.94);
		var out = null;
		for (i in 0...10) out = e.update(100.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testEwmaVolatilityNonNegative() {
		var e = new EwmaVolatility(0.9);
		for (i in 0...30) {
			var out = e.update(100.0 + Math.sin(i * 0.5) * 10.0);
			if (out != null) Assert.isTrue(out >= 0.0);
		}
	}

	// ── Expectancy ────────────────────────────────────────────────────────

	public function testExpectancyPositiveWithMoreWins() {
		var e = new Expectancy(10);
		var pnls = [10.0, -5.0, 10.0, -5.0, 10.0, -5.0, 10.0, -5.0, 10.0, 10.0];
		var out = null;
		for (p in pnls) out = e.update(p);
		Assert.notNull(out);
		Assert.isTrue(out > 0.0);
	}

	public function testExpectancyNegativeWithMoreLosses() {
		var e = new Expectancy(10);
		var pnls = [-10.0, 5.0, -10.0, 5.0, -10.0, 5.0, -10.0, 5.0, -10.0, -10.0];
		var out = null;
		for (p in pnls) out = e.update(p);
		Assert.notNull(out);
		Assert.isTrue(out < 0.0);
	}

	// ── CorrelationTrendIndicator ─────────────────────────────────────────

	public function testCorrelationTrendIndicatorPerfectUptrendIsOne() {
		var cti = new CorrelationTrendIndicator(10);
		var out = null;
		for (i in 1...15) out = cti.update(i * 2.0);
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-6);
	}

	public function testCorrelationTrendIndicatorPerfectDowntrendIsNegativeOne() {
		var cti = new CorrelationTrendIndicator(10);
		var out = null;
		for (i in 1...15) out = cti.update(100.0 - i * 2.0);
		Assert.notNull(out);
		Assert.floatEquals(-1.0, out, 1e-6);
	}

	public function testCorrelationTrendIndicatorBatchEqualsStreaming() {
		var prices = [for (i in 0...40) 100.0 + Math.sin(i * 0.3) * 6.0];
		var a = new CorrelationTrendIndicator(10), b = new CorrelationTrendIndicator(10);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
