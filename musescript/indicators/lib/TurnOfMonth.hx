package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Turn-of-Month Effect — ported from wickra-core's `TurnOfMonth`
 * (vendor/wickra/crates/wickra-core/src/indicators/turn_of_month.rs).
 *
 * The running mean of daily close-to-close returns for the sessions that
 * fall in the turn-of-month window (the first `n_first` calendar days plus
 * the last `n_last` days of a month). Each completed session (the
 * wall-clock day of the bar's timestamp shifted by `utc_offset_minutes`)
 * contributes its return `close / previous_close - 1`; sessions outside the
 * window are ignored. The classic effect uses `n_first = 3`, `n_last = 1`.
 */
class TurnOfMonth implements MuseIndicator<Bar, Float> {
	var nFirst:Int;
	var nLast:Int;
	var utcOffset:Int;
	var day:Null<{year:Int, month:Int, day:Int}>;
	var curClose:Float;
	var prevDayClose:Null<Float>;
	var sum:Float;
	var count:Int;

	public function new(nFirst:Int, nLast:Int, utcOffsetMinutes:Int) {
		if (nFirst == 0 && nLast == 0) throw "TurnOfMonth: n_first and n_last must not both be zero";
		this.nFirst = nFirst;
		this.nLast = nLast;
		this.utcOffset = utcOffsetMinutes;
		this.day = null;
		this.curClose = 0.0;
		this.prevDayClose = null;
		this.sum = 0.0;
		this.count = 0;
	}

	/** Classic turn-of-month window: first 3 and last 1 day of the month. */
	public static function classic():TurnOfMonth {
		return new TurnOfMonth(3, 1, 0);
	}

	/** Configured `(n_first, n_last, utc_offset_minutes)`. */
	public function params():{nFirst:Int, nLast:Int, utcOffsetMinutes:Int} {
		return {nFirst: nFirst, nLast: nLast, utcOffsetMinutes: utcOffset};
	}

	/** Most recent mean turn-of-month return if any in-window day has completed. */
	public function value():Null<Float> {
		return count == 0 ? null : sum / count;
	}

	/** Whether a day-of-month lies in the turn-of-month window. */
	static function inTurnWindow(dom:Int, dim:Int, nFirst:Int, nLast:Int):Bool {
		// Rust uses dim.saturating_sub(n_last): clamp at zero.
		var cutoff = dim - nLast;
		if (cutoff < 0) cutoff = 0;
		return dom <= nFirst || dom > cutoff;
	}

	static function isLeap(year:Int):Bool {
		return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
	}

	static function daysInMonth(year:Int, month:Int):Int {
		return switch (month) {
			case 1 | 3 | 5 | 7 | 8 | 10 | 12: 31;
			case 4 | 6 | 9 | 11: 30;
			default: isLeap(year) ? 29 : 28;
		};
	}

	/** Settle the just-finished day whose last close is `curClose`, then start `nextKey`. */
	function rollInto(year:Int, month:Int, dom:Int, nextKey:{year:Int, month:Int, day:Int}, close:Float):Void {
		if (prevDayClose != null) {
			var prev:Float = prevDayClose;
			var ret = prev == 0.0 ? 0.0 : curClose / prev - 1.0;
			if (inTurnWindow(dom, daysInMonth(year, month), nFirst, nLast)) {
				sum += ret;
				count += 1;
			}
		}
		prevDayClose = curClose;
		day = nextKey;
		curClose = close;
	}

	public function update(bar:Bar):Null<Float> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		var key = {year: civil.year, month: civil.month, day: civil.day};
		if (day == null) {
			day = key;
			curClose = bar.close;
		} else if (day.year == key.year && day.month == key.month && day.day == key.day) {
			curClose = bar.close;
		} else {
			rollInto(day.year, day.month, day.day, key, bar.close);
		}
		return value();
	}

	public function reset():Void {
		day = null;
		curClose = 0.0;
		prevDayClose = null;
		sum = 0.0;
		count = 0;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return count > 0;
	public function name():String return "TurnOfMonth";

	public static function spec():IndicatorSpec {
		return {
			name: "turn_of_month", args: [TWindow, TWindow, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var nf = IndicatorCache.intArg(args, 0, 3);
				var nl = IndicatorCache.intArg(args, 1, 1);
				var off = IndicatorCache.intArg(args, 2, 0);
				return IndicatorCache.evalBar(h, "turn_of_month:" + nf + ":" + nl + ":" + off, Math.NaN,
					() -> new TurnOfMonth(nf, nl, off), (i, b) -> (cast i : TurnOfMonth).update(b));
			}
		};
	}
}

/**
 * Faithful private copy of wickra-core's `calendar::civil_from_timestamp`
 * (vendor/wickra/crates/wickra-core/src/calendar.rs), taking unix seconds
 * (MuseScript `Bar.time`) where the Rust takes epoch milliseconds — the Rust
 * floors ms to seconds first, so the arithmetic below is identical.
 */
private class Civil {
	public static function fromTime(timeSecs:Float, utcOffsetMinutes:Int):{year:Int, month:Int, day:Int, hour:Int, minute:Int, weekday:Int, minuteOfDay:Int} {
		var localSecs = Math.floor(timeSecs) + utcOffsetMinutes * 60.0;
		var days = Math.floor(localSecs / 86400.0);
		var secsOfDay = localSecs - days * 86400.0;
		var hour = Std.int(secsOfDay / 3600.0);
		var minute = Std.int((secsOfDay - hour * 3600.0) / 60.0);
		var z = Std.int(days);
		var weekday = ((z + 3) % 7 + 7) % 7;
		var ymd = civilFromDays(z);
		return {
			year: ymd.year, month: ymd.month, day: ymd.day,
			hour: hour, minute: minute, weekday: weekday,
			minuteOfDay: hour * 60 + minute
		};
	}

	static function civilFromDays(z:Int):{year:Int, month:Int, day:Int} {
		z += 719468;
		var era = Std.int((z >= 0 ? z : z - 146096) / 146097);
		var doe = z - era * 146097;
		var yoe = Std.int((doe - Std.int(doe / 1460) + Std.int(doe / 36524) - Std.int(doe / 146096)) / 365);
		var y = yoe + era * 400;
		var doy = doe - (365 * yoe + Std.int(yoe / 4) - Std.int(yoe / 100));
		var mp = Std.int((5 * doy + 2) / 153);
		var day = doy - Std.int((153 * mp + 2) / 5) + 1;
		var month = mp < 10 ? mp + 3 : mp - 9;
		return {year: month <= 2 ? y + 1 : y, month: month, day: day};
	}
}
