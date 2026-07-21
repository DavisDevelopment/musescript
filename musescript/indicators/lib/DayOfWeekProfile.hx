package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Day-of-Week Profile output: per-weekday mean return, Monday first. Always length 7. */
typedef DayOfWeekProfileOutput = {
	var bins:Array<Float>;
}

/**
 * Day-of-Week Profile — ported from wickra-core's `DayOfWeekProfile`
 * (vendor/wickra/crates/wickra-core/src/indicators/day_of_week_profile.rs).
 *
 * Mean bar return bucketed by local weekday (Monday `0` .. Sunday `6`). Each
 * bar's simple return `close / previous_close - 1` is accumulated into the
 * bucket of its local weekday (the wall-clock day of the bar's timestamp
 * shifted by `utc_offset_minutes`), and the profile reports the running mean
 * per weekday. The first bar produces no output.
 *
 * MuseScript's `Bar.time` carries unix SECONDS where the Rust `Candle`
 * carries epoch milliseconds; the Rust calendar floors ms to seconds before
 * decomposing, so the civil-date arithmetic here is identical.
 */
class DayOfWeekProfile implements MuseIndicator<Bar, DayOfWeekProfileOutput> {
	static inline var DAYS:Int = 7;

	var utcOffset:Int;
	var prevClose:Null<Float>;
	var sum:Array<Float>;
	var count:Array<Int>;
	var last:Null<DayOfWeekProfileOutput>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffset = utcOffsetMinutes;
		this.prevClose = null;
		this.sum = [for (_ in 0...DAYS) 0.0];
		this.count = [for (_ in 0...DAYS) 0];
		this.last = null;
	}

	/** Configured UTC offset in minutes. */
	public function utcOffsetMinutes():Int return utcOffset;

	/** Most recent profile if at least one return has been recorded. */
	public function value():Null<DayOfWeekProfileOutput> return last;

	function snapshot():DayOfWeekProfileOutput {
		return {bins: [for (i in 0...DAYS) count[i] > 0 ? sum[i] / count[i] : 0.0]};
	}

	public function update(bar:Bar):Null<DayOfWeekProfileOutput> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		var result:Null<DayOfWeekProfileOutput> = null;
		if (prevClose != null) {
			var prev:Float = prevClose;
			var ret = prev == 0.0 ? 0.0 : bar.close / prev - 1.0;
			var day = civil.weekday;
			sum[day] += ret;
			count[day] += 1;
			var out = snapshot();
			this.last = out;
			result = out;
		}
		prevClose = bar.close;
		return result;
	}

	public function reset():Void {
		prevClose = null;
		for (i in 0...DAYS) {
			sum[i] = 0.0;
			count[i] = 0;
		}
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "DayOfWeekProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "day_of_week_profile", args: [TScalar], ret: TObject([
				{name: "bins", ty: TVector}
			]), minArgs: 0,
			eval: function(h, args) {
				var off = IndicatorCache.intArg(args, 0, 0);
				var nanFill:DayOfWeekProfileOutput = {bins: [for (_ in 0...7) Math.NaN]};
				return IndicatorCache.evalBar(h, "day_of_week_profile:" + off, nanFill,
					() -> new DayOfWeekProfile(off), (i, b) -> (cast i : DayOfWeekProfile).update(b));
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
		// 1970-01-01 was a Thursday; Monday-based weekday is (z + 3) mod 7.
		var weekday = ((z + 3) % 7 + 7) % 7;
		var ymd = civilFromDays(z);
		return {
			year: ymd.year, month: ymd.month, day: ymd.day,
			hour: hour, minute: minute, weekday: weekday,
			minuteOfDay: hour * 60 + minute
		};
	}

	/** Howard Hinnant's `civil_from_days` (chrono-compatible low-level date algorithms). */
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
