package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Overnight Gap — ported from wickra-core's `OvernightGap`
 * (vendor/wickra/crates/wickra-core/src/indicators/overnight_gap.rs).
 *
 * Close-to-open overnight gap as a simple return. At every local day
 * boundary the indicator computes `open / previous_close - 1`, where
 * `previous_close` is the close of the last bar of the prior session and
 * `open` is the open of the first bar of the new session. The value holds
 * for the rest of the session until the next boundary. The boundary is the
 * wall-clock day of the bar's timestamp shifted by `utc_offset_minutes`.
 * The first session yields no gap.
 */
class OvernightGap implements MuseIndicator<Bar, Float> {
	var utcOffset:Int;
	var dayKey:Null<{year:Int, month:Int, day:Int}>;
	var lastClose:Null<Float>;
	var gap:Null<Float>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffset = utcOffsetMinutes;
		this.dayKey = null;
		this.lastClose = null;
		this.gap = null;
	}

	/** Configured UTC offset in minutes. */
	public function utcOffsetMinutes():Int return utcOffset;

	/** Most recent overnight gap if at least one day boundary has been crossed. */
	public function value():Null<Float> return gap;

	public function update(bar:Bar):Null<Float> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		if (dayKey == null || dayKey.year != civil.year || dayKey.month != civil.month || dayKey.day != civil.day) {
			if (lastClose != null) {
				var prevClose:Float = lastClose;
				gap = prevClose == 0.0 ? 0.0 : bar.open / prevClose - 1.0;
			}
			dayKey = {year: civil.year, month: civil.month, day: civil.day};
		}
		lastClose = bar.close;
		return gap;
	}

	public function reset():Void {
		dayKey = null;
		lastClose = null;
		gap = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return gap != null;
	public function name():String return "OvernightGap";

	public static function spec():IndicatorSpec {
		return {
			name: "overnight_gap", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var off = IndicatorCache.intArg(args, 0, 0);
				return IndicatorCache.evalBar(h, "overnight_gap:" + off, Math.NaN,
					() -> new OvernightGap(off), (i, b) -> (cast i : OvernightGap).update(b));
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
