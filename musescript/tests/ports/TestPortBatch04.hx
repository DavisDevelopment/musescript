package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.AvgPrice;
import musescript.indicators.lib.BalanceOfPower;
import musescript.indicators.lib.Autocorrelation;
import musescript.indicators.lib.AverageDrawdown;
import musescript.indicators.lib.BandpassFilter;
import musescript.indicators.lib.AwesomeOscillatorHistogram;
import musescript.indicators.lib.AverageDailyRange;

/**
 * Batch 04: 7 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 *
 * Skipped: auto_fib (pattern-detection tool, not a streaming scalar indicator).
 */
class TestPortBatch04 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Float):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: i, index: Std.int(i) };
	}

	static function flatBar(price:Float, volume:Float, i:Float):Bar {
		return bar(price, price, price, price, volume, i);
	}

	// ── AvgPrice ────────────────────────────────────────────────────────────

	public function testAvgPriceReferenceValue() {
		// (open + high + low + close) / 4 = (10 + 14 + 6 + 12) / 4 = 10.5
		var bars = [bar(10.0, 14.0, 6.0, 12.0, 1.0, 0)];
		var ind = new AvgPrice();
		var out = IndicatorBatch.run(ind, bars);
		Assert.floatEquals(10.5, out[0]);
	}

	public function testAvgPriceEmitsFromFirstCandle() {
		var bars = [bar(10.0, 14.0, 6.0, 12.0, 1.0, 0)];
		var ind = new AvgPrice();
		Assert.equals(1, ind.warmupPeriod());
		Assert.isFalse(ind.isReady());
		Assert.notNull(ind.update(bars[0]));
		Assert.isTrue(ind.isReady());
	}

	public function testAvgPriceBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 2.0, base + 1.0, 10.0, i);
		}];
		var a = new AvgPrice(), b = new AvgPrice();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── BalanceOfPower ─────────────────────────────────────────────────────

	public function testBalanceOfPowerReferenceValue() {
		// (close - open) / (high - low) = (12 - 10) / (14 - 10) = 0.5
		var bars = [bar(10.0, 14.0, 10.0, 12.0, 0.0, 0)];
		var ind = new BalanceOfPower();
		var out = IndicatorBatch.run(ind, bars);
		Assert.floatEquals(0.5, out[0]);
	}

	public function testBalanceOfPowerCloseOnHighAfterOpenOnLowIsOne() {
		// open == low, close == high -> BOP = +1
		var bars = [bar(9.0, 11.0, 9.0, 11.0, 0.0, 0)];
		var ind = new BalanceOfPower();
		var out = IndicatorBatch.run(ind, bars);
		Assert.floatEquals(1.0, out[0]);
	}

	public function testBalanceOfPowerZeroRangeYieldsZero() {
		var bars = [bar(10.0, 10.0, 10.0, 10.0, 1.0, 0)];
		var ind = new BalanceOfPower();
		var out = IndicatorBatch.run(ind, bars);
		Assert.floatEquals(0.0, out[0]);
	}

	public function testBalanceOfPowerBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base, base + 2.0, base - 2.0, base + 1.0, i, i);
		}];
		var a = new BalanceOfPower(), b = new BalanceOfPower();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) Assert.floatEquals(batched[i], streamed[i]);
	}

	// ── Autocorrelation ──────────────────────────────────────────────────────

	public function testAutocorrelationConstantSeriesYieldsZero() {
		var prices = [42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0,
		              42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0,
		              42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0, 42.0];
		var a = new Autocorrelation(10, 1);
		var out = IndicatorBatch.run(a, prices);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testAutocorrelationAlternatingSeriesLagOneIsNegative() {
		// [−1, 1, −1, 1, …] alternates each step
		var prices:Array<Float> = [];
		for (i in 0...20) prices.push(i % 2 == 0 ? -1.0 : 1.0);
		var a = new Autocorrelation(10, 1);
		var out = IndicatorBatch.run(a, prices);
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.isTrue(last < -0.5, "alternating series should be strongly negative");
	}

	public function testAutocorrelationBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...60) prices.push(Math.sin(i * 0.3));
		var batch = IndicatorBatch.run(new Autocorrelation(14, 2), prices);
		var b = new Autocorrelation(14, 2);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batch.length) {
			if (batch[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batch[i], streamed[i]);
		}
	}

	// ── AverageDrawdown ──────────────────────────────────────────────────────

	public function testAverageDrawdownPureUptrendYieldsZero() {
		var prices:Array<Float> = [];
		for (i in 1...21) prices.push(i);
		var a = new AverageDrawdown(5);
		var out = IndicatorBatch.run(a, prices);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testAverageDrawdownReferenceValue() {
		// window [100, 120, 90, 110]: one drawdown episode, depth = (120 - 90) / 120 = 0.25
		var prices = [100.0, 120.0, 90.0, 110.0];
		var a = new AverageDrawdown(4);
		var out = IndicatorBatch.run(a, prices);
		Assert.floatEquals(0.25, out[3]);
	}

	public function testAverageDrawdownAveragesDistinctEpisodes() {
		// [100, 90, 100, 80, 100]: episode 1 depth 0.10, episode 2 depth 0.20, mean = 0.15
		var prices = [100.0, 90.0, 100.0, 80.0, 100.0];
		var a = new AverageDrawdown(5);
		var out = IndicatorBatch.run(a, prices);
		Assert.floatEquals(0.15, out[4]);
	}

	public function testAverageDrawdownBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...40) prices.push(100.0 + Math.sin(i * 0.3) * 8.0);
		var batch = IndicatorBatch.run(new AverageDrawdown(10), prices);
		var b = new AverageDrawdown(10);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batch.length) {
			if (batch[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batch[i], streamed[i]);
		}
	}

	// ── BandpassFilter ──────────────────────────────────────────────────────

	public function testBandpassFilterConstantInputStaysZero() {
		var prices = [50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0,
		              50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0];
		var bp = new BandpassFilter(20, 0.3);
		var out = IndicatorBatch.run(bp, prices);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v, 1e-9);
	}

	public function testBandpassFilterFirstBarsAreZero() {
		var bp = new BandpassFilter(20, 0.3);
		Assert.floatEquals(0.0, bp.update(100.0));
		Assert.floatEquals(0.0, bp.update(101.0));
	}

	public function testBandpassFilterBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...120) prices.push(100.0 + Math.sin(i * 0.25) * 9.0);
		var batch = IndicatorBatch.run(new BandpassFilter(20, 0.3), prices);
		var b = new BandpassFilter(20, 0.3);
		var streamed = [for (x in prices) b.update(x)];
		for (i in 0...batch.length) {
			if (batch[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batch[i], streamed[i]);
		}
	}

	// ── AwesomeOscillatorHistogram ───────────────────────────────────────────

	public function testAwesomeOscillatorHistogramConstantSeriesYieldsZero() {
		var bars = [for (i in 0...30) flatBar(42.0, 1.0, i)];
		var hist = new AwesomeOscillatorHistogram(3, 5, 1);
		var out = IndicatorBatch.run(hist, bars);
		var warmup = hist.warmupPeriod();
		for (i in warmup - 1...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testAwesomeOscillatorHistogramWarmupEmitsAtWarmupPeriod() {
		var bars = [for (i in 0...8) bar(10.0 + i, 10.0 + i, 10.0 + i, 10.0 + i, 1.0, i)];
		var hist = new AwesomeOscillatorHistogram(2, 4, 2);
		Assert.equals(6, hist.warmupPeriod());
		var out = IndicatorBatch.run(hist, bars);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
	}

	public function testAwesomeOscillatorHistogramBatchEqualsStreaming() {
		var bars:Array<Bar> = [];
		for (i in 0...100) {
			var price = 100.0 + Math.sin(i * 0.3) * 5.0;
			bars.push(bar(price, price + 0.5, price - 0.5, price, 1.0, i));
		}
		var a = AwesomeOscillatorHistogram.classic();
		var b = AwesomeOscillatorHistogram.classic();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── AverageDailyRange ────────────────────────────────────────────────────

	public function testAverageDailyRangeAveragesCompletedDayRanges() {
		var hour:Float = 3_600_000;
		var day:Float = 24 * hour;
		var adr = new AverageDailyRange(3, 0);
		// Day 1, bar 1: high 110, low 100.
		var v1 = adr.update(bar(105.0, 110.0, 100.0, 108.0, 1.0, 0));
		Assert.isNull(v1);
		// Day 1, bar 2 (same day): extends the day's high to 112 -> day range 12.
		var v2 = adr.update(bar(108.0, 112.0, 106.0, 109.0, 1.0, hour));
		Assert.isNull(v2);
		// Day 2 opens -> day 1 completes: ADR = 112 - 100 = 12
		var v3 = adr.update(bar(108.0, 120.0, 110.0, 109.0, 1.0, day));
		Assert.notNull(v3);
		Assert.floatEquals(12.0, v3);
		Assert.isTrue(adr.isReady());
	}

	public function testAverageDailyRangeRollsOffOldestDayBeyondPeriod() {
		var day:Float = 24 * 3_600_000;
		var adr = new AverageDailyRange(2, 0);
		adr.update(bar(105.0, 110.0, 100.0, 108.0, 1.0, 0)); // day 1 range 10
		var v = adr.update(bar(108.0, 125.0, 110.0, 109.0, 1.0, day)); // close day 1, open day 2
		Assert.floatEquals(10.0, v);
		// Close day 2 (range 15) -> window [10, 15], mean 12.5
		var v2 = adr.update(bar(110.0, 130.0, 110.0, 109.0, 1.0, 2 * day));
		Assert.floatEquals(12.5, v2);
		// Close day 3 (range 20) -> window [15, 20], oldest (10) rolled off, mean 17.5
		var v3 = adr.update(bar(138.0, 140.0, 138.0, 139.0, 1.0, 3 * day));
		Assert.floatEquals(17.5, v3);
	}

	public function testAverageDailyRangeBatchEqualsStreaming() {
		var hour:Float = 6 * 3_600_000;
		var bars:Array<Bar> = [];
		for (i in 0...60) {
			bars.push(bar(
				100.0 + (i % 5),
				110.0 + (i % 5),
				100.0 - (i % 3),
				105.0 + (i % 5),
				1.0,
				i * hour
			));
		}
		var a = new AverageDailyRange(4, 0);
		var b = new AverageDailyRange(4, 0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
