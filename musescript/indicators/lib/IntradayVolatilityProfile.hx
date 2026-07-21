package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Intraday Volatility Profile output: per-bucket return standard deviation, earliest bucket first. */
typedef IntradayVolatilityProfileOutput = {
	var bins:Array<Float>;
}

/**
 * Intraday Volatility Profile — ported from wickra-core's `IntradayVolatilityProfile`
 * (vendor/wickra/crates/wickra-core/src/indicators/intraday_volatility_profile.rs).
 *
 * Return volatility bucketed by local time of day. The local day (the
 * wall-clock day of the bar's timestamp shifted by `utc_offset_minutes`) is
 * split into `buckets` equal slices. Each bar's simple return
 * `close / previous_close - 1` updates the per-bucket running variance
 * (Welford), and the profile reports the per-bucket sample standard
 * deviation. Buckets with fewer than two samples read `0.0`. The first bar
 * produces no output.
 */
class IntradayVolatilityProfile implements MuseIndicator<Bar, IntradayVolatilityProfileOutput> {
	var buckets:Int;
	var utcOffset:Int;
	var prevClose:Null<Float>;
	var count:Array<Int>;
	var mean:Array<Float>;
	var m2:Array<Float>;
	var last:Null<IntradayVolatilityProfileOutput>;

	public function new(buckets:Int, utcOffsetMinutes:Int) {
		if (buckets <= 0) throw "IntradayVolatilityProfile: buckets must be > 0";
		this.buckets = buckets;
		this.utcOffset = utcOffsetMinutes;
		this.prevClose = null;
		this.count = [for (_ in 0...buckets) 0];
		this.mean = [for (_ in 0...buckets) 0.0];
		this.m2 = [for (_ in 0...buckets) 0.0];
		this.last = null;
	}

	/** Configured `(buckets, utc_offset_minutes)`. */
	public function params():{buckets:Int, utcOffsetMinutes:Int} {
		return {buckets: buckets, utcOffsetMinutes: utcOffset};
	}

	/** Most recent profile if at least one return has been recorded. */
	public function value():Null<IntradayVolatilityProfileOutput> return last;

	function bucketOf(minuteOfDay:Int):Int {
		var raw = Std.int((minuteOfDay * buckets) / 1440);
		return raw < buckets - 1 ? raw : buckets - 1;
	}

	function snapshot():IntradayVolatilityProfileOutput {
		return {bins: [for (i in 0...buckets) count[i] >= 2 ? Math.sqrt(m2[i] / (count[i] - 1)) : 0.0]};
	}

	public function update(bar:Bar):Null<IntradayVolatilityProfileOutput> {
		var civil = Civil.fromTime(bar.time, utcOffset);
		var result:Null<IntradayVolatilityProfileOutput> = null;
		if (prevClose != null) {
			var prev:Float = prevClose;
			var ret = prev == 0.0 ? 0.0 : bar.close / prev - 1.0;
			var bucket = bucketOf(civil.minuteOfDay);
			count[bucket] += 1;
			var delta = ret - mean[bucket];
			mean[bucket] += delta / count[bucket];
			var delta2 = ret - mean[bucket];
			m2[bucket] += delta * delta2;
			var out = snapshot();
			this.last = out;
			result = out;
		}
		prevClose = bar.close;
		return result;
	}

	public function reset():Void {
		prevClose = null;
		for (i in 0...buckets) {
			count[i] = 0;
			mean[i] = 0.0;
			m2[i] = 0.0;
		}
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "IntradayVolatilityProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "intraday_volatility_profile", args: [TWindow, TScalar], ret: TObject([
				{name: "bins", ty: TVector}
			]), minArgs: 1,
			eval: function(h, args) {
				var b = IndicatorCache.intArg(args, 0, 24);
				var off = IndicatorCache.intArg(args, 1, 0);
				var nanFill:IntradayVolatilityProfileOutput = {bins: [for (_ in 0...b) Math.NaN]};
				return IndicatorCache.evalBar(h, "intraday_volatility_profile:" + b + ":" + off, nanFill,
					() -> new IntradayVolatilityProfile(b, off), (i, bar) -> (cast i : IntradayVolatilityProfile).update(bar));
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
