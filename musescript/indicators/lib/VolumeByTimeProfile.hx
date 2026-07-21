package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Volume-by-Time Profile output: per-bucket mean volume, earliest bucket first. */
typedef VolumeByTimeProfileOutput = {
	var bins:Array<Float>;
}

/**
 * Volume-by-Time Profile — ported from wickra-core's `VolumeByTimeProfile`
 * (vendor/wickra/crates/wickra-core/src/indicators/volume_by_time_profile.rs).
 *
 * Mean traded volume bucketed by local time of day. The local day (the
 * wall-clock day of the bar's timestamp shifted by `utc_offset_minutes`) is
 * split into `buckets` equal slices. Each bar's volume is accumulated into
 * the bucket of its time-of-day, and the profile reports the running mean
 * volume per bucket. Unlike the return profiles, the first bar already
 * produces output (volume needs no prior bar).
 */
class VolumeByTimeProfile implements MuseIndicator<Bar, VolumeByTimeProfileOutput> {
	var buckets:Int;
	var utcOffset:Int;
	var sum:Array<Float>;
	var count:Array<Int>;
	var last:Null<VolumeByTimeProfileOutput>;

	public function new(buckets:Int, utcOffsetMinutes:Int) {
		if (buckets <= 0) throw "VolumeByTimeProfile: buckets must be > 0";
		this.buckets = buckets;
		this.utcOffset = utcOffsetMinutes;
		this.sum = [for (_ in 0...buckets) 0.0];
		this.count = [for (_ in 0...buckets) 0];
		this.last = null;
	}

	/** Configured `(buckets, utc_offset_minutes)`. */
	public function params():{buckets:Int, utcOffsetMinutes:Int} {
		return {buckets: buckets, utcOffsetMinutes: utcOffset};
	}

	/** Most recent profile if at least one bar has been seen. */
	public function value():Null<VolumeByTimeProfileOutput> return last;

	function bucketOf(minuteOfDay:Int):Int {
		var raw = Std.int((minuteOfDay * buckets) / 1440);
		return raw < buckets - 1 ? raw : buckets - 1;
	}

	function snapshot():VolumeByTimeProfileOutput {
		return {bins: [for (i in 0...buckets) count[i] > 0 ? sum[i] / count[i] : 0.0]};
	}

	public function update(bar:Bar):Null<VolumeByTimeProfileOutput> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		var bucket = bucketOf(civil.minuteOfDay);
		sum[bucket] += bar.volume;
		count[bucket] += 1;
		var out = snapshot();
		last = out;
		return out;
	}

	public function reset():Void {
		for (i in 0...buckets) {
			sum[i] = 0.0;
			count[i] = 0;
		}
		last = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return last != null;
	public function name():String return "VolumeByTimeProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "volume_by_time_profile", args: [TWindow, TScalar], ret: TObject([
				{name: "bins", ty: TVector}
			]), minArgs: 1,
			eval: function(h, args) {
				var b = IndicatorCache.intArg(args, 0, 24);
				var off = IndicatorCache.intArg(args, 1, 0);
				var nanFill:VolumeByTimeProfileOutput = {bins: [for (_ in 0...b) Math.NaN]};
				return IndicatorCache.evalBar(h, "volume_by_time_profile:" + b + ":" + off, nanFill,
					() -> new VolumeByTimeProfile(b, off), (i, bar) -> (cast i : VolumeByTimeProfile).update(bar));
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
