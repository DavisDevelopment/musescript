package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Overnight/Intraday decomposition of the current session's return. */
typedef OvernightIntradayReturnOutput = {
	var overnight:Float;
	var intraday:Float;
}

/**
 * Overnight vs. Intraday Return — ported from wickra-core's `OvernightIntradayReturn`
 * (vendor/wickra/crates/wickra-core/src/indicators/overnight_intraday_return.rs).
 *
 * Decomposes a session's total return into its overnight (close-to-open)
 * and intraday (open-to-close) components, re-anchored at each local day
 * boundary of the bar's timestamp shifted by `utc_offset_minutes`.
 * `overnight` is fixed at the session open (`open / previous_close - 1`);
 * `intraday` updates with every bar (`close / open - 1`). The first session
 * yields no output.
 */
class OvernightIntradayReturn implements MuseIndicator<Bar, OvernightIntradayReturnOutput> {
	var utcOffset:Int;
	var dayKey:Null<{year:Int, month:Int, day:Int}>;
	var lastClose:Null<Float>;
	var todayOpen:Float;
	var overnight:Null<Float>;
	var last:Null<OvernightIntradayReturnOutput>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffset = utcOffsetMinutes;
		this.dayKey = null;
		this.lastClose = null;
		this.todayOpen = 0.0;
		this.overnight = null;
		this.last = null;
	}

	/** Configured UTC offset in minutes. */
	public function utcOffsetMinutes():Int return utcOffset;

	/** Most recent decomposition if at least one day boundary has been crossed. */
	public function value():Null<OvernightIntradayReturnOutput> return last;

	public function update(bar:Bar):Null<OvernightIntradayReturnOutput> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		if (dayKey == null || dayKey.year != civil.year || dayKey.month != civil.month || dayKey.day != civil.day) {
			if (lastClose != null) {
				var prevClose:Float = lastClose;
				overnight = prevClose == 0.0 ? 0.0 : bar.open / prevClose - 1.0;
			}
			todayOpen = bar.open;
			dayKey = {year: civil.year, month: civil.month, day: civil.day};
		}
		lastClose = bar.close;
		if (overnight == null) return null;
		var intraday = todayOpen == 0.0 ? 0.0 : bar.close / todayOpen - 1.0;
		var out:OvernightIntradayReturnOutput = {overnight: overnight, intraday: intraday};
		last = out;
		return out;
	}

	public function reset():Void {
		dayKey = null;
		lastClose = null;
		todayOpen = 0.0;
		overnight = null;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "OvernightIntradayReturn";

	public static function spec():IndicatorSpec {
		return {
			name: "overnight_intraday_return", args: [TScalar], ret: TObject([
				{name: "overnight", ty: TScalar}, {name: "intraday", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var off = IndicatorCache.intArg(args, 0, 0);
				return IndicatorCache.evalBar(h, "overnight_intraday_return:" + off, {overnight: Math.NaN, intraday: Math.NaN},
					() -> new OvernightIntradayReturn(off), (i, b) -> (cast i : OvernightIntradayReturn).update(b));
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
