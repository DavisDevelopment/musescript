package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Session VWAP — ported from wickra-core's `SessionVwap`
 * (vendor/wickra/crates/wickra-core/src/indicators/session_vwap.rs).
 *
 * Volume-weighted average price reset at each local day boundary. Each bar
 * contributes its typical price `(high + low + close) / 3` weighted by
 * volume; the running VWAP is `Σ(typical · volume) / Σ volume` over the
 * current session. If the session's volume is still zero the indicator
 * falls back to the latest typical price so the output is always finite.
 * The session boundary is the wall-clock day of the bar's timestamp shifted
 * by `utc_offset_minutes`.
 */
class SessionVwap implements MuseIndicator<Bar, Float> {
	var utcOffset:Int;
	var dayKey:Null<{year:Int, month:Int, day:Int}>;
	var cumPv:Float;
	var cumVolume:Float;
	var last:Null<Float>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffset = utcOffsetMinutes;
		this.dayKey = null;
		this.cumPv = 0.0;
		this.cumVolume = 0.0;
		this.last = null;
	}

	/** Configured UTC offset in minutes. */
	public function utcOffsetMinutes():Int return utcOffset;

	/** Most recent VWAP if at least one bar has been seen. */
	public function value():Null<Float> return last;

	public function update(bar:Bar):Null<Float> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		if (dayKey == null || dayKey.year != civil.year || dayKey.month != civil.month || dayKey.day != civil.day) {
			dayKey = {year: civil.year, month: civil.month, day: civil.day};
			cumPv = 0.0;
			cumVolume = 0.0;
		}
		var typical = (bar.high + bar.low + bar.close) / 3.0;
		cumPv += typical * bar.volume;
		cumVolume += bar.volume;
		var vwap = cumVolume > 0.0 ? cumPv / cumVolume : typical;
		last = vwap;
		return vwap;
	}

	public function reset():Void {
		dayKey = null;
		cumPv = 0.0;
		cumVolume = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return last != null;
	public function name():String return "SessionVwap";

	public static function spec():IndicatorSpec {
		return {
			name: "session_vwap", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var off = IndicatorCache.intArg(args, 0, 0);
				return IndicatorCache.evalBar(h, "session_vwap:" + off, Math.NaN,
					() -> new SessionVwap(off), (i, b) -> (cast i : SessionVwap).update(b));
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
