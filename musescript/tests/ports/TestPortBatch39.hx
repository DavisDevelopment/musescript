package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.DayOfWeekProfile;
import musescript.indicators.lib.IntradayVolatilityProfile;
import musescript.indicators.lib.SessionHighLow;
import musescript.indicators.lib.SessionRange;
import musescript.indicators.lib.SessionVwap;
import musescript.indicators.lib.TimeOfDayReturnProfile;
import musescript.indicators.lib.TurnOfMonth;
import musescript.indicators.lib.OvernightGap;
import musescript.indicators.lib.OvernightIntradayReturn;
import musescript.indicators.lib.TpoProfile;
import musescript.indicators.lib.ValueArea;
import musescript.indicators.lib.VolumeProfile;
import musescript.indicators.lib.VolumeByTimeProfile;
import musescript.indicators.lib.NakedPoc;
import musescript.indicators.lib.SinglePrints;
import musescript.indicators.lib.HighLowVolumeNodes;
import musescript.indicators.lib.ProfileShape;

/**
 * Batch 39: 17 volume/time-profile & session-study indicators ported from
 * wickra-core. Known-value cases transcribed directly from the Rust fixture
 * blocks (timestamps converted from Wickra's epoch-milliseconds to
 * MuseScript Bar.time epoch-seconds — the Rust calendar floors ms to seconds
 * first, so the civil dates are identical).
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch39 extends Test {
	// Wickra's test constants were HOUR = 3_600_000 ms and DAY = 24 * HOUR;
	// Bar.time is unix seconds, so the same instants are HOUR = 3600 s etc.
	static inline var HOUR:Float = 3600.0;
	static inline var DAY:Float = 86400.0;
	// 2021-01-28 00:00 UTC (Rust: 1_611_792_000_000 ms).
	static inline var JAN28_2021:Float = 1611792000.0;

	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, t:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: t, index: i };
	}

	/** Rust `c(close, ts)`: flat candle at one price, volume 1. */
	static function flatC(close:Float, t:Float, i:Int):Bar {
		return bar(close, close, close, close, 1.0, t, i);
	}

	/** Rust session-test `c(high, low, ts)`: open=close=mid. */
	static function hlBar(high:Float, low:Float, t:Float, i:Int):Bar {
		var mid = (high + low) / 2.0;
		return bar(mid, high, low, mid, 1.0, t, i);
	}

	/** Rust profile-test `c(high, low, volume)`: open=close=mid, ts 0. */
	static function hlvBar(high:Float, low:Float, volume:Float, i:Int):Bar {
		var mid = (high + low) / 2.0;
		return bar(mid, high, low, mid, volume, 0.0, i);
	}

	/** Rust NakedPoc-test `c(high, low, close, volume)`: open=mid, ts 0. */
	static function hlcvBar(high:Float, low:Float, close:Float, volume:Float, i:Int):Bar {
		return bar((high + low) / 2.0, high, low, close, volume, 0.0, i);
	}

	/** Rust OHLCV `c(open, high, low, close, volume, ts)`. */
	static function ohlcvBar(o:Float, h:Float, l:Float, c:Float, v:Float, t:Float, i:Int):Bar {
		return bar(o, h, l, c, v, t, i);
	}

	static function assertBinsEqual(expected:Array<Float>, actual:Array<Float>) {
		Assert.equals(expected.length, actual.length);
		for (i in 0...expected.length) {
			Assert.floatEquals(expected[i], actual[i]);
		}
	}

	// ── DayOfWeekProfile ─────────────────────────────────────────────────────

	public function testDayOfWeekProfileMetadataAndAccessors() {
		var prof = new DayOfWeekProfile(60);
		Assert.equals(60, prof.utcOffsetMinutes());
		Assert.equals("DayOfWeekProfile", prof.name());
		Assert.equals(2, prof.warmupPeriod());
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
	}

	public function testDayOfWeekProfileBucketsByWeekday() {
		var prof = new DayOfWeekProfile(0);
		// 1970-01-01 Thursday (3); 01-02 Friday (4).
		Assert.isNull(prof.update(flatC(100.0, 0.0, 0)));
		var out = prof.update(flatC(101.0, DAY, 1)); // Friday return +0.01
		Assert.notNull(out);
		Assert.equals(7, out.bins.length);
		Assert.floatEquals(0.01, out.bins[4]); // Friday
		Assert.floatEquals(0.0, out.bins[3]); // Thursday had no return
		Assert.isTrue(prof.isReady());
	}

	public function testDayOfWeekProfileAveragesSameWeekdayAcrossWeeks() {
		var prof = new DayOfWeekProfile(0);
		prof.update(flatC(100.0, 0.0, 0)); // Thu
		prof.update(flatC(101.0, DAY, 1)); // Fri +0.01
		prof.update(flatC(100.0, 7 * DAY, 2)); // day 7 -> Thu
		var out = prof.update(flatC(103.0, 8 * DAY, 3)); // day 8 -> Fri
		Assert.isTrue(out.bins[4] > 0.0);
	}

	public function testDayOfWeekProfileZeroPrevCloseUsesZeroReturn() {
		var prof = new DayOfWeekProfile(0);
		prof.update(flatC(0.0, 0.0, 0));
		var out = prof.update(flatC(5.0, DAY, 1));
		Assert.floatEquals(0.0, out.bins[4]); // Friday, guarded return 0
	}

	public function testDayOfWeekProfileResetClearsState() {
		var prof = new DayOfWeekProfile(0);
		prof.update(flatC(100.0, 0.0, 0));
		prof.update(flatC(101.0, DAY, 1));
		prof.reset();
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
		Assert.isNull(prof.update(flatC(100.0, 2 * DAY, 2)));
	}

	public function testDayOfWeekProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...30) flatC(100.0 + (i % 5), i * DAY, i)];
		var a = new DayOfWeekProfile(0);
		var b = new DayOfWeekProfile(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				assertBinsEqual(batched[i].bins, streamed[i].bins);
			}
		}
	}

	// ── IntradayVolatilityProfile ────────────────────────────────────────────

	public function testIntradayVolatilityProfileRejectsZeroBuckets() {
		Assert.raises(function() new IntradayVolatilityProfile(0, 0));
	}

	public function testIntradayVolatilityProfileMetadataAndAccessors() {
		var prof = new IntradayVolatilityProfile(24, 90);
		Assert.equals(24, prof.params().buckets);
		Assert.equals(90, prof.params().utcOffsetMinutes);
		Assert.equals("IntradayVolatilityProfile", prof.name());
		Assert.equals(2, prof.warmupPeriod());
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
	}

	public function testIntradayVolatilityProfileSingleSampleBucketHasZeroVol() {
		var prof = new IntradayVolatilityProfile(24, 0);
		Assert.isNull(prof.update(flatC(100.0, 0.0, 0)));
		var out = prof.update(flatC(101.0, HOUR, 1));
		Assert.equals(24, out.bins.length);
		Assert.floatEquals(0.0, out.bins[1]); // only one sample in bucket 1
		Assert.isTrue(prof.isReady());
	}

	public function testIntradayVolatilityProfileStdMatchesManualTwoSamples() {
		var prof = new IntradayVolatilityProfile(24, 0);
		prof.update(flatC(100.0, 0.0, 0)); // 00:00
		prof.update(flatC(101.0, HOUR, 1)); // 01:00 r=0.01 into bucket 1
		// Next day 01:00, r2 = 0.03 into bucket 1.
		var out = prof.update(flatC(101.0 * 1.03, 25 * HOUR, 2));
		var mean = 0.02;
		var expected = Math.sqrt((Math.pow(0.01 - mean, 2) + Math.pow(0.03 - mean, 2)) / 1.0);
		Assert.floatEquals(expected, out.bins[1]);
	}

	public function testIntradayVolatilityProfileZeroPrevCloseUsesZeroReturn() {
		var prof = new IntradayVolatilityProfile(4, 0);
		prof.update(flatC(0.0, 0.0, 0));
		var out = prof.update(flatC(5.0, HOUR, 1));
		Assert.floatEquals(0.0, out.bins[0]);
	}

	public function testIntradayVolatilityProfileResetClearsState() {
		var prof = new IntradayVolatilityProfile(24, 0);
		prof.update(flatC(100.0, 0.0, 0));
		prof.update(flatC(101.0, HOUR, 1));
		prof.reset();
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
		Assert.isNull(prof.update(flatC(100.0, DAY, 2)));
	}

	public function testIntradayVolatilityProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...50) flatC(100.0 + (i % 6), i * HOUR, i)];
		var a = new IntradayVolatilityProfile(12, 0);
		var b = new IntradayVolatilityProfile(12, 0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				assertBinsEqual(batched[i].bins, streamed[i].bins);
			}
		}
	}

	// ── SessionHighLow ───────────────────────────────────────────────────────

	public function testSessionHighLowMetadataAndAccessors() {
		var shl = new SessionHighLow(-300);
		Assert.equals(-300, shl.utcOffsetMinutes());
		Assert.equals("SessionHighLow", shl.name());
		Assert.equals(1, shl.warmupPeriod());
		Assert.isTrue(!shl.isReady());
		Assert.isNull(shl.value());
	}

	public function testSessionHighLowTracksHighLowWithinDay() {
		var shl = new SessionHighLow(0);
		var first = shl.update(hlBar(105.0, 99.0, 0.0, 0));
		Assert.floatEquals(105.0, first.high);
		Assert.floatEquals(99.0, first.low);
		Assert.isTrue(shl.isReady());
		var second = shl.update(hlBar(108.0, 100.0, HOUR, 1));
		Assert.floatEquals(108.0, second.high);
		Assert.floatEquals(99.0, second.low);
		// A narrower bar does not shrink the range.
		var third = shl.update(hlBar(106.0, 101.0, 2 * HOUR, 2));
		Assert.floatEquals(108.0, third.high);
		Assert.floatEquals(99.0, third.low);
		// A bar with a lower low extends the range downward (same day).
		var fourth = shl.update(hlBar(107.0, 95.0, 3 * HOUR, 3));
		Assert.floatEquals(108.0, fourth.high);
		Assert.floatEquals(95.0, fourth.low);
	}

	public function testSessionHighLowReAnchorsOnNewDay() {
		var shl = new SessionHighLow(0);
		shl.update(hlBar(105.0, 99.0, 0.0, 0));
		shl.update(hlBar(108.0, 100.0, HOUR, 1));
		var next = shl.update(hlBar(51.0, 49.0, 24 * HOUR, 2));
		Assert.floatEquals(51.0, next.high);
		Assert.floatEquals(49.0, next.low);
	}

	public function testSessionHighLowUtcOffsetShiftsDayBoundary() {
		// Two bars 1h apart straddling UTC midnight. At UTC they are different
		// days; at +120 min they fall on the same local day.
		var pre = 23 * HOUR;
		var post = 24 * HOUR;
		var utc = new SessionHighLow(0);
		utc.update(hlBar(105.0, 99.0, pre, 0));
		var rolled = utc.update(hlBar(108.0, 100.0, post, 1));
		Assert.floatEquals(108.0, rolled.high);
		Assert.floatEquals(100.0, rolled.low); // re-anchored

		var shifted = new SessionHighLow(120);
		shifted.update(hlBar(105.0, 99.0, pre, 0));
		var same = shifted.update(hlBar(108.0, 100.0, post, 1));
		Assert.floatEquals(108.0, same.high);
		Assert.floatEquals(99.0, same.low); // same local day, range kept
	}

	public function testSessionHighLowResetClearsState() {
		var shl = new SessionHighLow(0);
		shl.update(hlBar(105.0, 99.0, 0.0, 0));
		shl.reset();
		Assert.isTrue(!shl.isReady());
		Assert.isNull(shl.value());
		var after = shl.update(hlBar(60.0, 50.0, HOUR, 1));
		Assert.floatEquals(60.0, after.high);
		Assert.floatEquals(50.0, after.low);
	}

	public function testSessionHighLowBatchEqualsStreaming() {
		var bars = [for (i in 0...30) hlBar(100.0 + i, 90.0 + i * 0.5, i * HOUR, i)];
		var a = new SessionHighLow(0);
		var b = new SessionHighLow(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i].high, streamed[i].high);
			Assert.floatEquals(batched[i].low, streamed[i].low);
		}
	}

	// ── SessionRange ─────────────────────────────────────────────────────────

	public function testSessionRangeMetadataAndAccessors() {
		var sr = new SessionRange(60);
		Assert.equals(60, sr.utcOffsetMinutes());
		Assert.equals("SessionRange", sr.name());
		Assert.equals(1, sr.warmupPeriod());
		Assert.isTrue(!sr.isReady());
		Assert.isNull(sr.value());
	}

	public function testSessionRangeAssignsBarsToSessions() {
		var sr = new SessionRange(0);
		var asia = sr.update(hlBar(104.0, 98.0, 2 * HOUR, 0));
		Assert.floatEquals(6.0, asia.asia);
		Assert.floatEquals(0.0, asia.eu);
		Assert.floatEquals(0.0, asia.us);
		Assert.isTrue(sr.isReady());
		var eu = sr.update(hlBar(110.0, 100.0, 10 * HOUR, 1));
		Assert.floatEquals(10.0, eu.eu);
		var us = sr.update(hlBar(120.0, 118.0, 20 * HOUR, 2));
		Assert.floatEquals(2.0, us.us);
		Assert.floatEquals(6.0, us.asia);
	}

	public function testSessionRangeWidensWithinOneSession() {
		var sr = new SessionRange(0);
		sr.update(hlBar(104.0, 98.0, HOUR, 0));
		var wider = sr.update(hlBar(106.0, 95.0, 3 * HOUR, 1));
		Assert.floatEquals(11.0, wider.asia);
	}

	public function testSessionRangeResetsSessionsOnNewDay() {
		var sr = new SessionRange(0);
		sr.update(hlBar(104.0, 98.0, 2 * HOUR, 0));
		sr.update(hlBar(110.0, 100.0, 10 * HOUR, 1));
		var next = sr.update(hlBar(101.0, 99.0, (24 + 2) * HOUR, 2));
		Assert.floatEquals(2.0, next.asia);
		Assert.floatEquals(0.0, next.eu);
	}

	public function testSessionRangeUtcOffsetMovesBarBetweenSessions() {
		// 07:00 UTC is Asia; shifted +120 min it becomes 09:00 -> EU.
		var utc = new SessionRange(0);
		var a = utc.update(hlBar(104.0, 98.0, 7 * HOUR, 0));
		Assert.floatEquals(6.0, a.asia);
		Assert.floatEquals(0.0, a.eu);

		var shifted = new SessionRange(120);
		var e = shifted.update(hlBar(104.0, 98.0, 7 * HOUR, 0));
		Assert.floatEquals(0.0, e.asia);
		Assert.floatEquals(6.0, e.eu);
	}

	public function testSessionRangeResetClearsState() {
		var sr = new SessionRange(0);
		sr.update(hlBar(104.0, 98.0, 2 * HOUR, 0));
		sr.reset();
		Assert.isTrue(!sr.isReady());
		Assert.isNull(sr.value());
	}

	public function testSessionRangeBatchEqualsStreaming() {
		var bars = [for (i in 0...40) hlBar(100.0 + (i % 5), 95.0 - (i % 3), i * HOUR, i)];
		var a = new SessionRange(0);
		var b = new SessionRange(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i].asia, streamed[i].asia);
			Assert.floatEquals(batched[i].eu, streamed[i].eu);
			Assert.floatEquals(batched[i].us, streamed[i].us);
		}
	}

	// ── SessionVwap ──────────────────────────────────────────────────────────

	public function testSessionVwapMetadataAndAccessors() {
		var vwap = new SessionVwap(-480);
		Assert.equals(-480, vwap.utcOffsetMinutes());
		Assert.equals("SessionVwap", vwap.name());
		Assert.equals(1, vwap.warmupPeriod());
		Assert.isTrue(!vwap.isReady());
		Assert.isNull(vwap.value());
	}

	public function testSessionVwapVolumeWeightsTheAverage() {
		var vwap = new SessionVwap(0);
		var first = vwap.update(bar(100.0, 100.0, 100.0, 100.0, 10.0, 0.0, 0));
		Assert.floatEquals(100.0, first);
		Assert.isTrue(vwap.isReady());
		var second = vwap.update(bar(110.0, 110.0, 110.0, 110.0, 30.0, HOUR, 1));
		Assert.floatEquals(107.5, second);
	}

	public function testSessionVwapZeroVolumeSessionFallsBackToTypical() {
		var vwap = new SessionVwap(0);
		var v = vwap.update(bar(100.0, 100.0, 100.0, 100.0, 0.0, 0.0, 0));
		Assert.floatEquals(100.0, v);
		var v2 = vwap.update(bar(120.0, 120.0, 120.0, 120.0, 0.0, HOUR, 1));
		Assert.floatEquals(120.0, v2);
	}

	public function testSessionVwapReAnchorsOnNewDay() {
		var vwap = new SessionVwap(0);
		vwap.update(bar(100.0, 100.0, 100.0, 100.0, 10.0, 0.0, 0));
		vwap.update(bar(110.0, 110.0, 110.0, 110.0, 30.0, HOUR, 1));
		// New day: VWAP restarts from the first bar of day 2.
		var next = vwap.update(bar(200.0, 200.0, 200.0, 200.0, 5.0, 24 * HOUR, 2));
		Assert.floatEquals(200.0, next);
	}

	public function testSessionVwapTypicalPriceUsesHighLowClose() {
		var vwap = new SessionVwap(0);
		// typical = (120 + 90 + 102) / 3 = 104.
		var v = vwap.update(bar(100.0, 120.0, 90.0, 102.0, 10.0, 0.0, 0));
		Assert.floatEquals(104.0, v);
	}

	public function testSessionVwapResetClearsState() {
		var vwap = new SessionVwap(0);
		vwap.update(bar(100.0, 100.0, 100.0, 100.0, 10.0, 0.0, 0));
		vwap.reset();
		Assert.isTrue(!vwap.isReady());
		Assert.isNull(vwap.value());
		var after = vwap.update(bar(50.0, 50.0, 50.0, 50.0, 1.0, HOUR, 1));
		Assert.floatEquals(50.0, after);
	}

	public function testSessionVwapBatchEqualsStreaming() {
		var bars = [for (i in 0...30) {
			var p = 100.0 + i;
			bar(p, p, p, p, 1.0 + (i % 4), i * HOUR, i);
		}];
		var a = new SessionVwap(0);
		var b = new SessionVwap(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── TimeOfDayReturnProfile ───────────────────────────────────────────────

	public function testTimeOfDayReturnProfileRejectsZeroBuckets() {
		Assert.raises(function() new TimeOfDayReturnProfile(0, 0));
	}

	public function testTimeOfDayReturnProfileMetadataAndAccessors() {
		var prof = new TimeOfDayReturnProfile(24, -300);
		Assert.equals(24, prof.params().buckets);
		Assert.equals(-300, prof.params().utcOffsetMinutes);
		Assert.equals("TimeOfDayReturnProfile", prof.name());
		Assert.equals(2, prof.warmupPeriod());
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
	}

	public function testTimeOfDayReturnProfileBucketsByHourAndMeansReturns() {
		var prof = new TimeOfDayReturnProfile(24, 0);
		Assert.isNull(prof.update(flatC(100.0, 0.0, 0))); // 00:00, no return
		// 01:00 return +0.01 -> bucket 1.
		var out = prof.update(flatC(101.0, HOUR, 1));
		Assert.equals(24, out.bins.length);
		Assert.floatEquals(0.01, out.bins[1]);
		Assert.floatEquals(0.0, out.bins[0]);
		Assert.isTrue(prof.isReady());
		// 01:00 next day, return -> averages into bucket 1.
		var out2 = prof.update(flatC(102.01, 25 * HOUR, 2));
		// two returns in bucket 1: 0.01 and 0.01 -> mean 0.01.
		Assert.floatEquals(0.01, out2.bins[1]);
	}

	public function testTimeOfDayReturnProfileLastBucketClampedForEndOfDay() {
		var prof = new TimeOfDayReturnProfile(24, 0);
		prof.update(flatC(100.0, 23 * HOUR, 0));
		// 23:59 -> minute 1439 -> bucket min(23, 23) = 23.
		var out = prof.update(flatC(110.0, 23 * HOUR + 59 * 60.0, 1));
		Assert.floatEquals(0.10, out.bins[23]);
	}

	public function testTimeOfDayReturnProfileZeroPrevCloseUsesZeroReturn() {
		var prof = new TimeOfDayReturnProfile(4, 0);
		prof.update(flatC(0.0, 0.0, 0));
		var out = prof.update(flatC(5.0, HOUR, 1));
		Assert.floatEquals(0.0, out.bins[0]);
	}

	public function testTimeOfDayReturnProfileResetClearsState() {
		var prof = new TimeOfDayReturnProfile(24, 0);
		prof.update(flatC(100.0, 0.0, 0));
		prof.update(flatC(101.0, HOUR, 1));
		prof.reset();
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
		Assert.isNull(prof.update(flatC(100.0, 2 * HOUR, 2)));
	}

	public function testTimeOfDayReturnProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...50) flatC(100.0 + (i % 7), i * HOUR, i)];
		var a = new TimeOfDayReturnProfile(12, 0);
		var b = new TimeOfDayReturnProfile(12, 0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				assertBinsEqual(batched[i].bins, streamed[i].bins);
			}
		}
	}

	// ── TurnOfMonth ──────────────────────────────────────────────────────────

	public function testTurnOfMonthRejectsEmptyWindow() {
		Assert.raises(function() new TurnOfMonth(0, 0, 0));
	}

	public function testTurnOfMonthMetadataAndAccessors() {
		var tom = TurnOfMonth.classic();
		Assert.equals(3, tom.params().nFirst);
		Assert.equals(1, tom.params().nLast);
		Assert.equals(0, tom.params().utcOffsetMinutes);
		Assert.equals("TurnOfMonth", tom.name());
		Assert.equals(2, tom.warmupPeriod());
		Assert.isTrue(!tom.isReady());
		Assert.isNull(tom.value());
	}

	public function testTurnOfMonthAveragesInWindowReturnsOnly() {
		var tom = new TurnOfMonth(3, 1, 0);
		// 2021-01-28 (out of window, no prior close): close 100.
		Assert.isNull(tom.update(flatC(100.0, JAN28_2021, 0)));
		// 2021-01-29 (out of window): return ignored.
		Assert.isNull(tom.update(flatC(110.0, JAN28_2021 + DAY, 1)));
		// 2021-01-30 (out of window): completes 01-29; still none.
		Assert.isNull(tom.update(flatC(120.0, JAN28_2021 + 2 * DAY, 2)));
		// 2021-01-31 (last day, in window): completes 01-30 (out). Still none.
		Assert.isNull(tom.update(flatC(121.0, JAN28_2021 + 3 * DAY, 3)));
		// 2021-02-01 (first day, in window): completes 01-31 (in window).
		// return = 121 / 120 - 1.
		var v = tom.update(flatC(130.0, JAN28_2021 + 4 * DAY, 4));
		Assert.floatEquals(121.0 / 120.0 - 1.0, v);
		Assert.isTrue(tom.isReady());
	}

	public function testTurnOfMonthZeroPrevCloseContributesZero() {
		var tom = new TurnOfMonth(3, 1, 0);
		// 2021-01-30 closes at 0 — becomes the prior close for 01-31.
		tom.update(flatC(0.0, JAN28_2021 + 2 * DAY, 0));
		// 2021-01-31 (in window): finalizes 01-30 with no prior -> no contribution.
		tom.update(flatC(5.0, JAN28_2021 + 3 * DAY, 1));
		// 2021-02-01 (in window): finalizes 01-31 with prev_close 0 -> ret 0.
		var v = tom.update(flatC(50.0, JAN28_2021 + 4 * DAY, 2));
		Assert.floatEquals(0.0, v);
	}

	public function testTurnOfMonthSameDayBarsUseLatestClose() {
		var tom = new TurnOfMonth(3, 1, 0);
		// 2021-01-30 closes at 100 (prior day, sets prev_day_close).
		tom.update(flatC(100.0, JAN28_2021 + 2 * DAY, 0));
		// 2021-01-31 two bars on the same day; the later close (120) wins.
		tom.update(flatC(110.0, JAN28_2021 + 3 * DAY, 1));
		tom.update(flatC(120.0, JAN28_2021 + 3 * DAY + HOUR, 2));
		// 2021-02-01 (in window) finalizes 01-31: return = 120 / 100 - 1 = 0.20.
		var v = tom.update(flatC(130.0, JAN28_2021 + 4 * DAY, 3));
		Assert.floatEquals(0.20, v);
	}

	public function testTurnOfMonthResetClearsState() {
		var tom = new TurnOfMonth(3, 1, 0);
		tom.update(flatC(121.0, JAN28_2021 + 3 * DAY, 0));
		tom.update(flatC(130.0, JAN28_2021 + 4 * DAY, 1));
		tom.reset();
		Assert.isTrue(!tom.isReady());
		Assert.isNull(tom.value());
	}

	public function testTurnOfMonthBatchEqualsStreaming() {
		var bars = [for (i in 0...40) flatC(100.0 + i, JAN28_2021 + i * DAY, i)];
		var a = new TurnOfMonth(3, 2, 0);
		var b = new TurnOfMonth(3, 2, 0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── OvernightGap ─────────────────────────────────────────────────────────

	static function gapBar(open:Float, close:Float, t:Float, i:Int):Bar {
		var high = Math.max(open, close);
		var low = Math.min(open, close);
		return bar(open, high, low, close, 1.0, t, i);
	}

	public function testOvernightGapMetadataAndAccessors() {
		var gap = new OvernightGap(330);
		Assert.equals(330, gap.utcOffsetMinutes());
		Assert.equals("OvernightGap", gap.name());
		Assert.equals(2, gap.warmupPeriod());
		Assert.isTrue(!gap.isReady());
		Assert.isNull(gap.value());
	}

	public function testOvernightGapFirstSessionHasNoGap() {
		var gap = new OvernightGap(0);
		Assert.isNull(gap.update(gapBar(99.0, 100.0, 0.0, 0)));
		// Same day, still no gap.
		Assert.isNull(gap.update(gapBar(100.0, 101.0, HOUR, 1)));
		Assert.isTrue(!gap.isReady());
	}

	public function testOvernightGapComputesGapAtDayBoundary() {
		var gap = new OvernightGap(0);
		gap.update(gapBar(99.0, 100.0, 0.0, 0)); // day 1 closes 100
		var g = gap.update(gapBar(105.0, 105.5, 24 * HOUR, 1));
		Assert.floatEquals(0.05, g);
		Assert.isTrue(gap.isReady());
		// Holds for the rest of the session.
		var same = gap.update(gapBar(106.0, 107.0, 25 * HOUR, 2));
		Assert.floatEquals(0.05, same);
	}

	public function testOvernightGapNegativeGapDown() {
		var gap = new OvernightGap(0);
		gap.update(gapBar(99.0, 100.0, 0.0, 0));
		var g = gap.update(gapBar(90.0, 91.0, 24 * HOUR, 1));
		Assert.floatEquals(-0.1, g);
	}

	public function testOvernightGapZeroPrevCloseYieldsZeroGap() {
		var gap = new OvernightGap(0);
		gap.update(gapBar(0.0, 0.0, 0.0, 0)); // degenerate day 1 closing at 0
		var g = gap.update(gapBar(5.0, 6.0, 24 * HOUR, 1));
		Assert.floatEquals(0.0, g);
	}

	public function testOvernightGapResetClearsState() {
		var gap = new OvernightGap(0);
		gap.update(gapBar(99.0, 100.0, 0.0, 0));
		gap.update(gapBar(105.0, 105.5, 24 * HOUR, 1));
		gap.reset();
		Assert.isTrue(!gap.isReady());
		Assert.isNull(gap.value());
		Assert.isNull(gap.update(gapBar(10.0, 11.0, 48 * HOUR, 2)));
	}

	public function testOvernightGapBatchEqualsStreaming() {
		var bars = [for (i in 0...50) gapBar(100.0 + (i % 7), 100.0 + (i % 5), i * 6 * HOUR, i)];
		var a = new OvernightGap(0);
		var b = new OvernightGap(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── OvernightIntradayReturn ──────────────────────────────────────────────

	static function oiBar(open:Float, close:Float, t:Float, i:Int):Bar {
		var high = Math.max(open, close) + 1.0;
		var low = Math.max(Math.min(open, close) - 1.0, 0.0);
		return bar(open, high, low, close, 1.0, t, i);
	}

	public function testOvernightIntradayReturnMetadataAndAccessors() {
		var oi = new OvernightIntradayReturn(-300);
		Assert.equals(-300, oi.utcOffsetMinutes());
		Assert.equals("OvernightIntradayReturn", oi.name());
		Assert.equals(2, oi.warmupPeriod());
		Assert.isTrue(!oi.isReady());
		Assert.isNull(oi.value());
	}

	public function testOvernightIntradayReturnFirstSessionYieldsNone() {
		var oi = new OvernightIntradayReturn(0);
		Assert.isNull(oi.update(oiBar(99.0, 100.0, 0.0, 0)));
		Assert.isNull(oi.update(oiBar(100.0, 102.0, HOUR, 1)));
		Assert.isTrue(!oi.isReady());
	}

	public function testOvernightIntradayReturnDecomposes() {
		var oi = new OvernightIntradayReturn(0);
		oi.update(oiBar(99.0, 100.0, 0.0, 0)); // day 1 close 100
		var v = oi.update(oiBar(110.0, 121.0, 24 * HOUR, 1));
		Assert.floatEquals(0.10, v.overnight);
		Assert.floatEquals(0.10, v.intraday);
		Assert.isTrue(oi.isReady());
	}

	public function testOvernightIntradayReturnIntradayUpdatesThroughSession() {
		var oi = new OvernightIntradayReturn(0);
		oi.update(oiBar(99.0, 100.0, 0.0, 0));
		oi.update(oiBar(110.0, 110.0, 24 * HOUR, 1)); // open 110, close 110 -> intraday 0
		var later = oi.update(oiBar(111.0, 132.0, 25 * HOUR, 2));
		Assert.floatEquals(0.10, later.overnight); // fixed at open
		Assert.floatEquals(0.20, later.intraday); // 132 / 110 - 1
	}

	public function testOvernightIntradayReturnZeroAnchorsYieldZeroComponents() {
		var oi = new OvernightIntradayReturn(0);
		oi.update(oiBar(1.0, 0.0, 0.0, 0)); // day 1 closes at 0
		// Day 2 opens at 0: overnight uses zero prev_close -> 0; intraday uses
		// zero today_open -> 0.
		var v = oi.update(bar(0.0, 5.0, 0.0, 4.0, 1.0, 24 * HOUR, 1));
		Assert.floatEquals(0.0, v.overnight);
		Assert.floatEquals(0.0, v.intraday);
	}

	public function testOvernightIntradayReturnResetClearsState() {
		var oi = new OvernightIntradayReturn(0);
		oi.update(oiBar(99.0, 100.0, 0.0, 0));
		oi.update(oiBar(110.0, 121.0, 24 * HOUR, 1));
		oi.reset();
		Assert.isTrue(!oi.isReady());
		Assert.isNull(oi.value());
		Assert.isNull(oi.update(oiBar(50.0, 55.0, 48 * HOUR, 2)));
	}

	public function testOvernightIntradayReturnBatchEqualsStreaming() {
		var bars = [for (i in 0...48) oiBar(100.0 + (i % 6), 100.0 + (i % 4), i * 8 * HOUR, i)];
		var a = new OvernightIntradayReturn(0);
		var b = new OvernightIntradayReturn(0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].overnight, streamed[i].overnight);
				Assert.floatEquals(batched[i].intraday, streamed[i].intraday);
			}
		}
	}

	// ── TpoProfile ───────────────────────────────────────────────────────────

	public function testTpoProfileRejectsZeroParams() {
		Assert.raises(function() new TpoProfile(0, 50));
		Assert.raises(function() new TpoProfile(20, 0));
	}

	public function testTpoProfileAccessorsAndMetadata() {
		var tpo = new TpoProfile(30, 50);
		Assert.equals("TpoProfile", tpo.name());
		Assert.equals(30, tpo.warmupPeriod());
		Assert.equals(30, tpo.params().period);
		Assert.equals(50, tpo.params().binCount);
		Assert.isNull(tpo.value());
		Assert.isTrue(!tpo.isReady());
	}

	public function testTpoProfileClassicParams() {
		var tpo = TpoProfile.classic();
		Assert.equals(30, tpo.params().period);
		Assert.equals(50, tpo.params().binCount);
	}

	public function testTpoProfileWarmsUpOverPeriod() {
		var tpo = new TpoProfile(3, 4);
		Assert.isNull(tpo.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 0.0, 0)));
		Assert.isNull(tpo.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 1.0, 1)));
		Assert.notNull(tpo.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 2.0, 2)));
		Assert.isTrue(tpo.isReady());
	}

	public function testTpoProfileReferenceCounts() {
		// Window of 2 candles, 4 bins, domain 10..14, width 1.
		// bar0: 10..14 touches bins 0,1,2,3 -> +1 each.
		// bar1: 11..12 touches bins 1,2 -> +1 each.
		// counts = [1, 2, 2, 1]. TPO is volume-agnostic.
		var tpo = new TpoProfile(2, 4);
		Assert.isNull(tpo.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 5.0, 0.0, 0)));
		var out = tpo.update(ohlcvBar(11.0, 12.0, 11.0, 11.5, 999.0, 1.0, 1));
		Assert.floatEquals(10.0, out.priceLow);
		Assert.floatEquals(14.0, out.priceHigh);
		Assert.equals(4, out.counts.length);
		Assert.floatEquals(1.0, out.counts[0]);
		Assert.floatEquals(2.0, out.counts[1]);
		Assert.floatEquals(2.0, out.counts[2]);
		Assert.floatEquals(1.0, out.counts[3]);
	}

	public function testTpoProfileVolumeIndependent() {
		var a = new TpoProfile(2, 4);
		var b = new TpoProfile(2, 4);
		a.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 1.0, 0.0, 0));
		var outA = a.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 1.0, 1.0, 1));
		b.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 9999.0, 0.0, 0));
		var outB = b.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 9999.0, 1.0, 1));
		assertBinsEqual(outA.counts, outB.counts);
	}

	public function testTpoProfileDegenerateSinglePriceWindow() {
		var tpo = new TpoProfile(3, 4);
		tpo.update(ohlcvBar(50.0, 50.0, 50.0, 50.0, 10.0, 0.0, 0));
		tpo.update(ohlcvBar(50.0, 50.0, 50.0, 50.0, 20.0, 1.0, 1));
		var out = tpo.update(ohlcvBar(50.0, 50.0, 50.0, 50.0, 30.0, 2.0, 2));
		Assert.floatEquals(50.0, out.priceLow);
		Assert.floatEquals(50.0, out.priceHigh);
		Assert.floatEquals(3.0, out.counts[0]);
		Assert.floatEquals(0.0, out.counts[1]);
	}

	public function testTpoProfileSinglePrintBarMarksOneBin() {
		// A single-print bar inside a wider domain marks exactly its own bin.
		var tpo = new TpoProfile(2, 4);
		tpo.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 5.0, 0.0, 0)); // domain setter
		var out = tpo.update(ohlcvBar(13.0, 13.0, 13.0, 13.0, 5.0, 1.0, 1));
		// domain 10..14, width 1; price 13 -> bin 3.
		Assert.floatEquals(2.0, out.counts[3]);
	}

	public function testTpoProfileResetClearsState() {
		var tpo = new TpoProfile(2, 4);
		tpo.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 0.0, 0));
		tpo.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 1.0, 1));
		Assert.isTrue(tpo.isReady());
		tpo.reset();
		Assert.isTrue(!tpo.isReady());
		Assert.isNull(tpo.value());
	}

	public function testTpoProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...30) {
			var base = 100.0 + (i % 7);
			ohlcvBar(base, base + 2.0, base - 2.0, base, 10.0 + i, i, i);
		}];
		var a = new TpoProfile(10, 16);
		var b = new TpoProfile(10, 16);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].priceLow, streamed[i].priceLow);
				Assert.floatEquals(batched[i].priceHigh, streamed[i].priceHigh);
				assertBinsEqual(batched[i].counts, streamed[i].counts);
			}
		}
	}

	// ── ValueArea ────────────────────────────────────────────────────────────

	public function testValueAreaRejectsInvalidParams() {
		Assert.raises(function() new ValueArea(0, 50, 0.7));
		Assert.raises(function() new ValueArea(20, 0, 0.7));
		Assert.raises(function() new ValueArea(20, 50, 0.0));
		Assert.raises(function() new ValueArea(20, 50, 1.5));
		Assert.raises(function() new ValueArea(20, 50, Math.NaN));
	}

	public function testValueAreaAccessorsAndMetadata() {
		var v = new ValueArea(20, 50, 0.7);
		Assert.equals(20, v.params().period);
		Assert.equals(50, v.params().binCount);
		Assert.floatEquals(0.7, v.params().valueAreaPct);
		Assert.equals("ValueArea", v.name());
		Assert.equals(20, v.warmupPeriod());
		Assert.isNull(v.value());
	}

	public function testValueAreaClassicIsConstructible() {
		var v = ValueArea.classic();
		Assert.equals(20, v.params().period);
		Assert.equals(50, v.params().binCount);
		Assert.floatEquals(0.70, v.params().valueAreaPct);
	}

	public function testValueAreaWarmupEmitsAfterPeriod() {
		var v = new ValueArea(5, 10, 0.7);
		for (i in 0...4) {
			Assert.isNull(v.update(ohlcvBar(100.0, 101.0, 99.0, 100.0, 10.0, i, i)));
		}
		var out = v.update(ohlcvBar(100.0, 101.0, 99.0, 100.0, 10.0, 4.0, 4));
		Assert.notNull(out);
		Assert.isTrue(out.vah >= out.poc);
		Assert.isTrue(out.poc >= out.val);
		Assert.isTrue(v.isReady());
	}

	public function testValueAreaConstantSinglePrintYieldsCollapsedValueArea() {
		// Every bar trades at exactly 100 — POC == VAH == VAL == 100.
		var v = new ValueArea(5, 20, 0.7);
		var last:Null<ValueAreaOutput> = null;
		for (i in 0...10) {
			var out = v.update(ohlcvBar(100.0, 100.0, 100.0, 100.0, 5.0, i, i));
			if (out != null) last = out;
		}
		Assert.floatEquals(100.0, last.poc);
		Assert.floatEquals(100.0, last.vah);
		Assert.floatEquals(100.0, last.val);
	}

	public function testValueAreaSinglePrintBarInMixedWindowDumpsVolumeIntoOneBin() {
		var bars = [
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 0.0, 0),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 1.0, 1),
			ohlcvBar(102.0, 102.0, 102.0, 102.0, 1000.0, 2.0, 2),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 3.0, 3),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 4.0, 4),
		];
		var v = new ValueArea(5, 50, 0.70);
		var last:Null<ValueAreaOutput> = null;
		for (b in bars) {
			var out = v.update(b);
			if (out != null) last = out;
		}
		// POC must sit in the high-volume bin that holds price 102.
		Assert.isTrue(last.poc >= 101.9 && last.poc <= 102.1, 'POC ${last.poc} not near 102');
	}

	public function testValueAreaConcentratedVolumeLocatesPocAtHighVolumeBar() {
		var bars = [
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 0.0, 0),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 1.0, 1),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 2.0, 2),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 1.0, 3.0, 3),
			ohlcvBar(110.0, 110.5, 109.5, 110.0, 1000.0, 4.0, 4),
		];
		var v = new ValueArea(5, 50, 0.70);
		var last:Null<ValueAreaOutput> = null;
		for (b in bars) {
			var out = v.update(b);
			if (out != null) last = out;
		}
		Assert.isTrue(last.poc >= 109.5 && last.poc <= 110.5, 'POC ${last.poc} not inside [109.5, 110.5]');
		Assert.isTrue(last.vah >= last.poc);
		Assert.isTrue(last.val <= last.poc);
	}

	public function testValueAreaBracketsPointOfControl() {
		var bars = [for (i in 0...30) {
			var base = 100.0 + Math.cos(i) * 2.0;
			ohlcvBar(base, base + 0.5, base - 0.5, base, 10.0, i, i);
		}];
		var v = new ValueArea(15, 30, 0.70);
		for (b in bars) {
			var o = v.update(b);
			if (o == null) continue;
			Assert.isTrue(o.vah >= o.poc, 'VAH ${o.vah} < POC ${o.poc}');
			Assert.isTrue(o.val <= o.poc, 'VAL ${o.val} > POC ${o.poc}');
		}
	}

	public function testValueAreaZeroVolumeBarsAreSkippedInHistogram() {
		// Only bar 4 carries any volume — output stays finite.
		var bars = [
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 0.0, 0.0, 0),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 0.0, 1.0, 1),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 0.0, 2.0, 2),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 0.0, 3.0, 3),
			ohlcvBar(100.0, 100.5, 99.5, 100.0, 50.0, 4.0, 4),
		];
		var v = new ValueArea(5, 20, 0.7);
		var last:Null<ValueAreaOutput> = null;
		for (b in bars) {
			var out = v.update(b);
			if (out != null) last = out;
		}
		Assert.isTrue(Math.isFinite(last.poc));
		Assert.isTrue(Math.isFinite(last.vah));
		Assert.isTrue(Math.isFinite(last.val));
	}

	public function testValueAreaResetClearsState() {
		var v = new ValueArea(5, 10, 0.7);
		for (i in 0...20) {
			v.update(ohlcvBar(100.0, 101.0, 99.0, 100.0, 10.0, i, i));
		}
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(ohlcvBar(100.0, 101.0, 99.0, 100.0, 10.0, 0.0, 0)));
	}

	public function testValueAreaBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i);
			ohlcvBar(base, base + 1.0, base - 1.0, base, 10.0 + i, i, i);
		}];
		var a = new ValueArea(10, 20, 0.7);
		var b = new ValueArea(10, 20, 0.7);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].poc, streamed[i].poc);
				Assert.floatEquals(batched[i].vah, streamed[i].vah);
				Assert.floatEquals(batched[i].val, streamed[i].val);
			}
		}
	}

	// ── VolumeProfile ────────────────────────────────────────────────────────

	public function testVolumeProfileRejectsZeroParams() {
		Assert.raises(function() new VolumeProfile(0, 50));
		Assert.raises(function() new VolumeProfile(20, 0));
	}

	public function testVolumeProfileAccessorsAndMetadata() {
		var vp = new VolumeProfile(20, 50);
		Assert.equals("VolumeProfile", vp.name());
		Assert.equals(20, vp.warmupPeriod());
		Assert.equals(20, vp.params().period);
		Assert.equals(50, vp.params().binCount);
		Assert.isNull(vp.value());
		Assert.isTrue(!vp.isReady());
	}

	public function testVolumeProfileClassicParams() {
		var vp = VolumeProfile.classic();
		Assert.equals(20, vp.params().period);
		Assert.equals(50, vp.params().binCount);
	}

	public function testVolumeProfileWarmsUpOverPeriod() {
		var vp = new VolumeProfile(3, 4);
		Assert.isNull(vp.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 0.0, 0)));
		Assert.isNull(vp.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 1.0, 1)));
		Assert.notNull(vp.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 2.0, 2)));
		Assert.isTrue(vp.isReady());
	}

	public function testVolumeProfileReferenceDistribution() {
		// Window of 2 candles, 4 bins.
		// bar0: single print at 10, vol 100 -> bin 0 gets 100.
		// bar1: 10..14, vol 80, spans 4 bins -> 20 each.
		// domain: low=10, high=14, width=1 -> bins = [120, 20, 20, 20].
		var vp = new VolumeProfile(2, 4);
		Assert.isNull(vp.update(ohlcvBar(10.0, 10.0, 10.0, 10.0, 100.0, 0.0, 0)));
		var out = vp.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 80.0, 1.0, 1));
		Assert.floatEquals(10.0, out.priceLow);
		Assert.floatEquals(14.0, out.priceHigh);
		Assert.equals(4, out.bins.length);
		Assert.floatEquals(120.0, out.bins[0]);
		Assert.floatEquals(20.0, out.bins[1]);
		Assert.floatEquals(20.0, out.bins[2]);
		Assert.floatEquals(20.0, out.bins[3]);
	}

	public function testVolumeProfileConservesTotalVolume() {
		var vp = new VolumeProfile(4, 8);
		var bars = [
			ohlcvBar(10.0, 12.0, 9.0, 11.0, 30.0, 0.0, 0),
			ohlcvBar(11.0, 13.0, 10.0, 12.0, 40.0, 1.0, 1),
			ohlcvBar(12.0, 14.0, 11.0, 13.0, 50.0, 2.0, 2),
			ohlcvBar(13.0, 15.0, 12.0, 14.0, 60.0, 3.0, 3),
		];
		var out:Null<VolumeProfileOutput> = null;
		for (b in bars) out = vp.update(b);
		var total = 0.0;
		for (v in out.bins) total += v;
		Assert.floatEquals(180.0, total);
	}

	public function testVolumeProfileDegenerateSinglePriceWindow() {
		var vp = new VolumeProfile(2, 4);
		vp.update(ohlcvBar(50.0, 50.0, 50.0, 50.0, 10.0, 0.0, 0));
		var out = vp.update(ohlcvBar(50.0, 50.0, 50.0, 50.0, 20.0, 1.0, 1));
		Assert.floatEquals(50.0, out.priceLow);
		Assert.floatEquals(50.0, out.priceHigh);
		Assert.floatEquals(30.0, out.bins[0]);
		Assert.floatEquals(0.0, out.bins[1]);
	}

	public function testVolumeProfileZeroVolumeBarsAreSkipped() {
		var vp = new VolumeProfile(2, 4);
		vp.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 0.0, 0.0, 0));
		var out = vp.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 40.0, 1.0, 1));
		var total = 0.0;
		for (v in out.bins) total += v;
		Assert.floatEquals(40.0, total);
	}

	public function testVolumeProfileRollingWindowDropsOldest() {
		var vp = new VolumeProfile(2, 4);
		vp.update(ohlcvBar(100.0, 100.0, 100.0, 100.0, 99.0, 0.0, 0));
		vp.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 40.0, 1.0, 1));
		// Third bar evicts the price-100 bar; domain is now 10..14 only.
		var out = vp.update(ohlcvBar(10.0, 14.0, 10.0, 12.0, 40.0, 2.0, 2));
		Assert.floatEquals(14.0, out.priceHigh);
		var total = 0.0;
		for (v in out.bins) total += v;
		Assert.floatEquals(80.0, total);
	}

	public function testVolumeProfileResetClearsState() {
		var vp = new VolumeProfile(2, 4);
		vp.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 0.0, 0));
		vp.update(ohlcvBar(10.0, 11.0, 9.0, 10.0, 5.0, 1.0, 1));
		Assert.isTrue(vp.isReady());
		vp.reset();
		Assert.isTrue(!vp.isReady());
		Assert.isNull(vp.value());
	}

	public function testVolumeProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...30) {
			var base = 100.0 + (i % 7);
			ohlcvBar(base, base + 2.0, base - 2.0, base, 10.0 + i, i, i);
		}];
		var a = new VolumeProfile(10, 16);
		var b = new VolumeProfile(10, 16);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].priceLow, streamed[i].priceLow);
				Assert.floatEquals(batched[i].priceHigh, streamed[i].priceHigh);
				assertBinsEqual(batched[i].bins, streamed[i].bins);
			}
		}
	}

	// ── VolumeByTimeProfile ──────────────────────────────────────────────────

	public function testVolumeByTimeProfileRejectsZeroBuckets() {
		Assert.raises(function() new VolumeByTimeProfile(0, 0));
	}

	public function testVolumeByTimeProfileMetadataAndAccessors() {
		var prof = new VolumeByTimeProfile(24, -60);
		Assert.equals(24, prof.params().buckets);
		Assert.equals(-60, prof.params().utcOffsetMinutes);
		Assert.equals("VolumeByTimeProfile", prof.name());
		Assert.equals(1, prof.warmupPeriod());
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
	}

	public function testVolumeByTimeProfileEmitsFromFirstBarAndMeansVolume() {
		var prof = new VolumeByTimeProfile(24, 0);
		var out = prof.update(bar(100.0, 100.0, 100.0, 100.0, 500.0, HOUR, 0)); // 01:00 -> bucket 1
		Assert.notNull(out);
		Assert.equals(24, out.bins.length);
		Assert.floatEquals(500.0, out.bins[1]);
		Assert.floatEquals(0.0, out.bins[0]);
		Assert.isTrue(prof.isReady());
		// Next day 01:00, volume 700 -> mean (500 + 700) / 2 = 600.
		var out2 = prof.update(bar(100.0, 100.0, 100.0, 100.0, 700.0, 25 * HOUR, 1));
		Assert.floatEquals(600.0, out2.bins[1]);
	}

	public function testVolumeByTimeProfileLastBucketClamped() {
		var prof = new VolumeByTimeProfile(24, 0);
		// 23:59 -> minute 1439 -> bucket 23.
		var out = prof.update(bar(100.0, 100.0, 100.0, 100.0, 300.0, 23 * HOUR + 59 * 60.0, 0));
		Assert.floatEquals(300.0, out.bins[23]);
	}

	public function testVolumeByTimeProfileResetClearsState() {
		var prof = new VolumeByTimeProfile(24, 0);
		prof.update(bar(100.0, 100.0, 100.0, 100.0, 500.0, HOUR, 0));
		prof.reset();
		Assert.isTrue(!prof.isReady());
		Assert.isNull(prof.value());
		var out = prof.update(bar(100.0, 100.0, 100.0, 100.0, 100.0, 2 * HOUR, 1));
		Assert.floatEquals(100.0, out.bins[2]);
	}

	public function testVolumeByTimeProfileBatchEqualsStreaming() {
		var bars = [for (i in 0...50) bar(100.0, 100.0, 100.0, 100.0, 100.0 + (i % 8), i * HOUR, i)];
		var a = new VolumeByTimeProfile(12, 0);
		var b = new VolumeByTimeProfile(12, 0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			assertBinsEqual(batched[i].bins, streamed[i].bins);
		}
	}

	// ── NakedPoc ─────────────────────────────────────────────────────────────

	public function testNakedPocRejectsZeroParams() {
		Assert.raises(function() new NakedPoc(0, 24));
		Assert.raises(function() new NakedPoc(20, 0));
	}

	public function testNakedPocAccessorsAndMetadata() {
		var n = new NakedPoc(20, 24);
		Assert.equals(20, n.params().sessionLen);
		Assert.equals(24, n.params().bins);
		Assert.equals(0, n.nakedCount());
		Assert.equals(20, n.warmupPeriod());
		Assert.equals("NakedPoc", n.name());
		Assert.isTrue(!n.isReady());
		Assert.isNull(n.value());
	}

	public function testNakedPocFirstEmissionAtSessionEnd() {
		var n = new NakedPoc(4, 8);
		var bars = [for (i in 0...6) hlcvBar(101.0, 99.0, 100.0, 1000.0, i)];
		var out = IndicatorBatch.run(n, bars);
		for (i in 0...3) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[3]);
	}

	public function testNakedPocRecordsSessionPoc() {
		var n = new NakedPoc(4, 16);
		for (i in 0...4) n.update(hlcvBar(101.0, 99.0, 100.0, 5000.0, i));
		Assert.equals(1, n.nakedCount());
		var poc = n.value();
		Assert.isTrue(Math.abs(poc - 100.0) < 2.0, 'POC should be near 100, got $poc');
	}

	public function testNakedPocRevisitMarksPocTested() {
		var n = new NakedPoc(4, 16);
		// Session 1 around 100 -> naked POC ~100.
		for (i in 0...4) n.update(hlcvBar(101.0, 99.0, 100.0, 5000.0, i));
		Assert.equals(1, n.nakedCount());
		// Trade away at 120 (does not cover 100) -> still naked.
		n.update(hlcvBar(121.0, 119.0, 120.0, 1000.0, 4));
		Assert.equals(1, n.nakedCount());
		// A candle whose range covers 100 -> POC tested -> removed.
		n.update(hlcvBar(121.0, 95.0, 100.0, 1000.0, 5));
		Assert.equals(0, n.nakedCount());
	}

	public function testNakedPocEmptyNakedReportsClose() {
		var n = new NakedPoc(4, 16);
		for (i in 0...4) n.update(hlcvBar(101.0, 99.0, 100.0, 5000.0, i));
		// Wipe the naked POC with a covering candle.
		var out = n.update(hlcvBar(121.0, 95.0, 117.0, 1000.0, 4));
		Assert.equals(0, n.nakedCount());
		Assert.floatEquals(117.0, out);
	}

	public function testNakedPocFlatSessionReportsPrice() {
		// A session with zero high-low span returns the session price directly.
		var n = new NakedPoc(2, 4);
		n.update(hlcvBar(50.0, 50.0, 50.0, 10.0, 0));
		Assert.floatEquals(50.0, n.update(hlcvBar(50.0, 50.0, 50.0, 10.0, 1)));
	}

	public function testNakedPocZeroVolumeSessionIsHandled() {
		var n = new NakedPoc(2, 4);
		n.update(hlcvBar(60.0, 40.0, 50.0, 0.0, 0));
		Assert.notNull(n.update(hlcvBar(60.0, 40.0, 50.0, 0.0, 1)));
	}

	public function testNakedPocNearestOfTwoNakedPocs() {
		// Two untouched POCs at distant prices accumulate; the one nearest the
		// last close is reported.
		var n = new NakedPoc(2, 4);
		n.update(hlcvBar(11.0, 9.0, 10.0, 100.0, 0));
		n.update(hlcvBar(11.0, 9.0, 10.0, 100.0, 1)); // POC near 10
		n.update(hlcvBar(101.0, 99.0, 100.0, 100.0, 2));
		var v = n.update(hlcvBar(101.0, 99.0, 100.0, 100.0, 3)); // POC near 100
		Assert.isTrue(v > 50.0, 'nearest to close 100 should be the upper POC, got $v');
	}

	public function testNakedPocResetClearsState() {
		var n = new NakedPoc(4, 8);
		for (i in 0...6) n.update(hlcvBar(101.0, 99.0, 100.0, 1000.0, i));
		Assert.isTrue(n.isReady());
		n.reset();
		Assert.isTrue(!n.isReady());
		Assert.isNull(n.value());
		Assert.equals(0, n.nakedCount());
	}

	public function testNakedPocBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.25) * 9.0;
			hlcvBar(base + 1.0, base - 1.0, base, 1000.0 + i, i);
		}];
		var a = new NakedPoc(20, 24);
		var b = new NakedPoc(20, 24);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── SinglePrints ─────────────────────────────────────────────────────────

	public function testSinglePrintsRejectsZeroParams() {
		Assert.raises(function() new SinglePrints(0, 24));
		Assert.raises(function() new SinglePrints(20, 0));
	}

	public function testSinglePrintsAccessorsAndMetadata() {
		var s = new SinglePrints(20, 24);
		Assert.equals(20, s.params().period);
		Assert.equals(24, s.params().bins);
		Assert.equals(20, s.warmupPeriod());
		Assert.equals("SinglePrints", s.name());
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.value());
	}

	public function testSinglePrintsFirstEmissionAtWarmupPeriod() {
		var s = new SinglePrints(4, 8);
		var bars = [for (i in 0...6) hlvBar(101.0 + i, 99.0 + i, 1000.0, i)];
		var out = IndicatorBatch.run(s, bars);
		for (i in 0...3) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[3]);
	}

	public function testSinglePrintsFlatRangeHasNoSinglePrints() {
		// Every bar covers the same single price -> zero span -> 0.
		var s = new SinglePrints(4, 8);
		var last:Null<Float> = null;
		for (i in 0...6) {
			var v = s.update(hlvBar(100.0, 100.0, 1000.0, i));
			if (v != null) last = v;
		}
		Assert.floatEquals(0.0, last);
	}

	public function testSinglePrintsRampHasManySinglePrints() {
		// A one-directional ramp visits most levels exactly once.
		var s = new SinglePrints(10, 24);
		var last:Null<Float> = null;
		for (i in 0...10) {
			var v = s.update(hlvBar(100.5 + i, 99.5 + i, 1000.0, i));
			if (v != null) last = v;
		}
		Assert.isTrue(last > 0.0, 'a ramp should produce single prints, got $last');
	}

	public function testSinglePrintsOutputNonNegative() {
		var s = new SinglePrints(14, 24);
		for (i in 0...60) {
			var v = s.update(hlvBar(110.0 + Math.sin(i * 0.3) * 8.0, 90.0, 1000.0, i));
			if (v != null) Assert.isTrue(v >= 0.0);
		}
	}

	public function testSinglePrintsResetClearsState() {
		var s = new SinglePrints(4, 8);
		for (i in 0...6) s.update(hlvBar(101.0 + i, 99.0 + i, 1000.0, i));
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.value());
		Assert.isNull(s.update(hlvBar(101.0, 99.0, 1000.0, 0)));
	}

	public function testSinglePrintsBatchEqualsStreaming() {
		var bars = [for (i in 0...80) hlvBar(110.0 + Math.sin(i * 0.25) * 9.0, 90.0, 1000.0, i)];
		var a = new SinglePrints(20, 24);
		var b = new SinglePrints(20, 24);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── HighLowVolumeNodes ───────────────────────────────────────────────────

	public function testHighLowVolumeNodesRejectsZeroParams() {
		Assert.raises(function() new HighLowVolumeNodes(0, 24));
		Assert.raises(function() new HighLowVolumeNodes(20, 0));
	}

	public function testHighLowVolumeNodesAccessorsAndMetadata() {
		var h = new HighLowVolumeNodes(20, 24);
		Assert.equals(20, h.params().period);
		Assert.equals(24, h.params().bins);
		Assert.equals(20, h.warmupPeriod());
		Assert.equals("HighLowVolumeNodes", h.name());
		Assert.isTrue(!h.isReady());
		Assert.isNull(h.value());
	}

	public function testHighLowVolumeNodesFirstEmissionAtWarmupPeriod() {
		var h = new HighLowVolumeNodes(4, 8);
		var bars = [for (i in 0...6) hlvBar(110.0, 90.0, 1000.0, i)];
		var out = IndicatorBatch.run(h, bars);
		for (i in 0...3) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[3]);
	}

	public function testHighLowVolumeNodesHvnAtHeavyPrice() {
		// Most bars cluster at ~100 (heavy volume); one bar pokes up to 120 lightly.
		var h = new HighLowVolumeNodes(6, 24);
		var last:Null<HighLowVolumeNodesOutput> = null;
		for (i in 0...5) {
			var v = h.update(hlvBar(101.0, 99.0, 5000.0, i));
			if (v != null) last = v;
		}
		var v = h.update(hlvBar(121.0, 119.0, 100.0, 5));
		if (v != null) last = v;
		Assert.isTrue(last.hvn < 110.0, 'HVN should be at the heavy cluster, got ${last.hvn}');
	}

	public function testHighLowVolumeNodesOutputsFinite() {
		var h = new HighLowVolumeNodes(10, 24);
		for (i in 0...30) {
			var o = h.update(hlvBar(110.0 + Math.sin(i * 0.3) * 5.0, 90.0, 1000.0 + i, i));
			if (o != null) {
				Assert.isTrue(Math.isFinite(o.hvn) && Math.isFinite(o.lvn));
			}
		}
	}

	public function testHighLowVolumeNodesFlatWindowIsHandled() {
		// Zero high-low span dumps all volume into bin 0 and returns early.
		var h = new HighLowVolumeNodes(2, 4);
		h.update(hlvBar(50.0, 50.0, 10.0, 0));
		Assert.notNull(h.update(hlvBar(50.0, 50.0, 10.0, 1)));
	}

	public function testHighLowVolumeNodesZeroVolumeWindowFallsBack() {
		// All-zero volume leaves no traded bin; the LVN falls back to the HVN.
		var h = new HighLowVolumeNodes(2, 4);
		h.update(hlvBar(60.0, 40.0, 0.0, 0));
		var out = h.update(hlvBar(60.0, 40.0, 0.0, 1));
		Assert.floatEquals(out.hvn, out.lvn);
	}

	public function testHighLowVolumeNodesResetClearsState() {
		var h = new HighLowVolumeNodes(4, 8);
		for (i in 0...6) h.update(hlvBar(110.0, 90.0, 1000.0, i));
		Assert.isTrue(h.isReady());
		h.reset();
		Assert.isTrue(!h.isReady());
		Assert.isNull(h.value());
		Assert.isNull(h.update(hlvBar(110.0, 90.0, 1000.0, 0)));
	}

	public function testHighLowVolumeNodesBatchEqualsStreaming() {
		var bars = [for (i in 0...80) hlvBar(110.0 + Math.sin(i * 0.25) * 9.0, 90.0, 1000.0 + i, i)];
		var a = new HighLowVolumeNodes(20, 24);
		var b = new HighLowVolumeNodes(20, 24);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].hvn, streamed[i].hvn);
				Assert.floatEquals(batched[i].lvn, streamed[i].lvn);
			}
		}
	}

	// ── ProfileShape ─────────────────────────────────────────────────────────

	public function testProfileShapeRejectsInvalidParams() {
		Assert.raises(function() new ProfileShape(0, 24));
		Assert.raises(function() new ProfileShape(20, 2));
	}

	public function testProfileShapeAccessorsAndMetadata() {
		var p = new ProfileShape(20, 24);
		Assert.equals(20, p.params().period);
		Assert.equals(24, p.params().bins);
		Assert.equals(20, p.warmupPeriod());
		Assert.equals("ProfileShape", p.name());
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
	}

	public function testProfileShapeFirstEmissionAtWarmupPeriod() {
		var p = new ProfileShape(4, 9);
		var bars = [for (i in 0...6) hlvBar(110.0, 90.0, 1000.0, i)];
		var out = IndicatorBatch.run(p, bars);
		for (i in 0...3) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[3]);
	}

	public function testProfileShapeHeavyTopIsPShape() {
		// Volume concentrated near the top of the range -> P-shape -> +1.
		var p = new ProfileShape(6, 9);
		var last:Null<Float> = null;
		for (i in 0...5) {
			var v = p.update(hlvBar(119.0, 117.0, 5000.0, i));
			if (v != null) last = v;
		}
		var v = p.update(hlvBar(119.0, 80.0, 50.0, 5)); // a thin tail down to 80
		if (v != null) last = v;
		Assert.floatEquals(1.0, last);
	}

	public function testProfileShapeHeavyBottomIsBShape() {
		var p = new ProfileShape(6, 9);
		var last:Null<Float> = null;
		for (i in 0...5) {
			var v = p.update(hlvBar(83.0, 81.0, 5000.0, i));
			if (v != null) last = v;
		}
		var v = p.update(hlvBar(120.0, 81.0, 50.0, 5)); // a thin tail up to 120
		if (v != null) last = v;
		Assert.floatEquals(-1.0, last);
	}

	public function testProfileShapeBalancedIsDShape() {
		// Volume concentrated in the middle -> D/normal -> 0.
		var p = new ProfileShape(6, 9);
		var last:Null<Float> = null;
		for (i in 0...5) {
			var v = p.update(hlvBar(101.0, 99.0, 5000.0, i));
			if (v != null) last = v;
		}
		var v = p.update(hlvBar(120.0, 80.0, 50.0, 5)); // thin tails both ways
		if (v != null) last = v;
		Assert.floatEquals(0.0, last);
	}

	public function testProfileShapeFlatWindowIsHandled() {
		// Zero high-low span skips the histogram pass entirely.
		var p = new ProfileShape(2, 4);
		p.update(hlvBar(50.0, 50.0, 10.0, 0));
		Assert.notNull(p.update(hlvBar(50.0, 50.0, 10.0, 1)));
	}

	public function testProfileShapeZeroVolumeWindowIsHandled() {
		// Non-flat window of zero-volume candles hits the skip path.
		var p = new ProfileShape(2, 4);
		p.update(hlvBar(60.0, 40.0, 0.0, 0));
		Assert.notNull(p.update(hlvBar(60.0, 40.0, 0.0, 1)));
	}

	public function testProfileShapeResetClearsState() {
		var p = new ProfileShape(4, 9);
		for (i in 0...6) p.update(hlvBar(110.0, 90.0, 1000.0, i));
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
		Assert.isNull(p.update(hlvBar(110.0, 90.0, 1000.0, 0)));
	}

	public function testProfileShapeBatchEqualsStreaming() {
		var bars = [for (i in 0...80) hlvBar(110.0 + Math.sin(i * 0.25) * 9.0, 90.0, 1000.0 + i, i)];
		var a = new ProfileShape(20, 24);
		var b = new ProfileShape(20, 24);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}
}
