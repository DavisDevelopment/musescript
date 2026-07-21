package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Session Range output: the current day's high−low range within each 8-hour session. */
typedef SessionRangeOutput = {
	var asia:Float;
	var eu:Float;
	var us:Float;
}

/**
 * Session Range — ported from wickra-core's `SessionRange`
 * (vendor/wickra/crates/wickra-core/src/indicators/session_range.rs).
 *
 * Per-session high-low range, keyed off the wall-clock hour of the bar's
 * timestamp shifted by `utc_offset_minutes`. The local day is split into
 * three eight-hour sessions: Asia `00:00..08:00`, EU `08:00..16:00`,
 * US `16:00..24:00`. Each session accumulates its own high / low; the
 * reported range is `high - low`, or `0.0` before that session has seen a
 * bar. All three re-anchor automatically at the day boundary.
 */
class SessionRange implements MuseIndicator<Bar, SessionRangeOutput> {
	var utcOffset:Int;
	var dayKey:Null<{year:Int, month:Int, day:Int}>;
	var sessHigh:Array<Float>;
	var sessLow:Array<Float>;
	var last:Null<SessionRangeOutput>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffset = utcOffsetMinutes;
		this.dayKey = null;
		this.sessHigh = [Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY];
		this.sessLow = [Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY];
		this.last = null;
	}

	/** Configured UTC offset in minutes. */
	public function utcOffsetMinutes():Int return utcOffset;

	/** Most recent output if at least one bar has been seen. */
	public function value():Null<SessionRangeOutput> return last;

	function rangeOf(i:Int):Float {
		return sessHigh[i] >= sessLow[i] ? sessHigh[i] - sessLow[i] : 0.0;
	}

	function snapshot():SessionRangeOutput {
		return {asia: rangeOf(0), eu: rangeOf(1), us: rangeOf(2)};
	}

	public function update(bar:Bar):Null<SessionRangeOutput> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		if (dayKey == null || dayKey.year != civil.year || dayKey.month != civil.month || dayKey.day != civil.day) {
			dayKey = {year: civil.year, month: civil.month, day: civil.day};
			for (i in 0...3) {
				sessHigh[i] = Math.NEGATIVE_INFINITY;
				sessLow[i] = Math.POSITIVE_INFINITY;
			}
		}
		var session = Std.int(civil.hour / 8); // 0 Asia, 1 EU, 2 US
		if (bar.high > sessHigh[session]) sessHigh[session] = bar.high;
		if (bar.low < sessLow[session]) sessLow[session] = bar.low;
		var out = snapshot();
		last = out;
		return out;
	}

	public function reset():Void {
		dayKey = null;
		for (i in 0...3) {
			sessHigh[i] = Math.NEGATIVE_INFINITY;
			sessLow[i] = Math.POSITIVE_INFINITY;
		}
		last = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return last != null;
	public function name():String return "SessionRange";

	public static function spec():IndicatorSpec {
		return {
			name: "session_range", args: [TScalar], ret: TObject([
				{name: "asia", ty: TScalar}, {name: "eu", ty: TScalar}, {name: "us", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var off = IndicatorCache.intArg(args, 0, 0);
				return IndicatorCache.evalBar(h, "session_range:" + off, {asia: Math.NaN, eu: Math.NaN, us: Math.NaN},
					() -> new SessionRange(off), (i, b) -> (cast i : SessionRange).update(b));
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
