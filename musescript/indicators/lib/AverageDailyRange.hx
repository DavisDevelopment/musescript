package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Average Daily Range (ADR) — ported from wickra-core's `AverageDailyRange`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/average_daily_range.rs).
 *
 * The indicator tracks the running high / low of the current session (the
 * wall-clock day of the bar's timestamp, shifted by `utc_offset_minutes`).
 * When a new day begins, the just-finished session's range (`high - low`) joins
 * a rolling window of the last `period` completed days, and the reported value
 * is their mean. The current, still-forming day is excluded until it closes.
 * No value is produced until the first session completes.
 */
class AverageDailyRange implements MuseIndicator<Bar, Float> {
	var period:Int;
	var utcOffsetMinutes:Int;
	var dayKey:Null<{year:Int, month:Int, day:Int}>;
	var curHigh:Float;
	var curLow:Float;
	var completed:Array<Float>;
	var sum:Float;

	public function new(period:Int, utcOffsetMinutes:Int) {
		if (period <= 0) throw "AverageDailyRange: period must be > 0";
		this.period = period;
		this.utcOffsetMinutes = utcOffsetMinutes;
		reset();
	}

	/**
	 * Extract year/month/day from timestamp (ms) with UTC offset.
	 * Assumes time is in milliseconds (JavaScript timestamp convention).
	 */
	static function getDateKey(timestamp:Float, utcOffsetMinutes:Int):{year:Int, month:Int, day:Int} {
		// Convert ms to seconds, then add offset in seconds
		var offsetSeconds = utcOffsetMinutes * 60;
		var adjTimestamp = (timestamp / 1000.0) + offsetSeconds;

		// Extract day-of-epoch and convert to calendar date
		// Epoch is 1970-01-01. This is a simplified conversion.
		// Days since epoch
		var daysSinceEpoch = Math.floor(adjTimestamp / 86400.0);

		// Zeller's congruence variant: convert days to Y/M/D
		// For simplicity, we use a lookup-free algorithm
		// Starting from 1970-01-01 (Thu), day 0
		var year = 1970;
		var days = daysSinceEpoch;

		// Advance by full years
		while (true) {
			var daysInYear = isLeapYear(year) ? 366 : 365;
			if (days < daysInYear) break;
			days -= daysInYear;
			year++;
		}

		// Now find month and day within the year
		var daysInMonth = isLeapYear(year) ? DAYS_IN_MONTH_LEAP : DAYS_IN_MONTH;
		var month = 1;
		while (month <= 12 && days >= daysInMonth[month - 1]) {
			days -= daysInMonth[month - 1];
			month++;
		}

		var day = Std.int(days) + 1;
		return {year: year, month: month, day: day};
	}

	static function isLeapYear(year:Int):Bool {
		return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
	}

	static var DAYS_IN_MONTH = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	static var DAYS_IN_MONTH_LEAP = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

	public function update(bar:Bar):Null<Float> {
		var civil = getDateKey(bar.time, utcOffsetMinutes);
		if (dayKey == null || dayKey.year != civil.year || dayKey.month != civil.month || dayKey.day != civil.day) {
			// Day changed
			if (dayKey != null) {
				// Close the previous day
				var range = curHigh - curLow;
				completed.push(range);
				sum += range;
				if (completed.length > period) {
					sum -= completed.shift();
				}
			}
			// Start new day
			dayKey = civil;
			curHigh = bar.high;
			curLow = bar.low;
		} else {
			// Same day: update high/low
			if (bar.high > curHigh) curHigh = bar.high;
			if (bar.low < curLow) curLow = bar.low;
		}

		// Return current value if available
		return if (completed.length == 0) null else sum / completed.length;
	}

	public function reset():Void {
		dayKey = null;
		curHigh = Math.NEGATIVE_INFINITY;
		curLow = Math.POSITIVE_INFINITY;
		completed = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return completed.length > 0;
	public function name():String return "AverageDailyRange";

	public static function spec():IndicatorSpec {
		return {
			name: "average_daily_range", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 5);
				return IndicatorCache.evalBar(h, "average_daily_range:" + p, Math.NaN,
					() -> new AverageDailyRange(p, 0), (i, b) -> (cast i : AverageDailyRange).update(b));
			}
		};
	}
}
