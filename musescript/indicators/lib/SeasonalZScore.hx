package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Seasonal Z-Score keyed on hour of day — ported from wickra-core's
 * `SeasonalZScore`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/seasonal_z_score.rs).
 *
 * For every bar the indicator forms the simple return
 * `close / previous_close − 1` and compares it to the running mean and
 * standard deviation of all prior returns that fell in the SAME local hour
 * (the wall-clock hour of the bar's timestamp shifted by
 * `utc_offset_minutes`). Output is `(return − hour_mean) / hour_std`. A
 * bucket needs at least two prior samples before it can emit; a bucket with
 * zero historical variance reports 0. Per-hour statistics use Welford's
 * online algorithm.
 *
 * Timestamp note: Rust `Candle.timestamp` is epoch MILLISECONDS and the hour
 * comes from `calendar::civil_from_timestamp` (floor/euclidean arithmetic);
 * MuseScript's `Bar.time` is epoch SECONDS, so `hourOf` mirrors the same
 * civil math from seconds — identical for any instant, including pre-epoch.
 */
class SeasonalZScore implements MuseIndicator<Bar, Float> {
	static inline var HOURS = 24;

	var utcOffsetMinutes:Int;
	var prevClose:Null<Float>;
	var count:Array<Int>;
	var mean:Array<Float>;
	var m2:Array<Float>;
	var last:Null<Float>;

	public function new(utcOffsetMinutes:Int) {
		this.utcOffsetMinutes = utcOffsetMinutes;
		reset();
	}

	/**
	 * Local wall-clock hour (0..23) of a unix-seconds instant, mirroring
	 * wickra's `civil_from_timestamp`: shift by the offset, then take
	 * floor-based (euclidean) seconds-of-day. Only the hour field of the
	 * civil decomposition is consumed by this indicator.
	 */
	static function hourOf(timeSecs:Float, utcOffsetMinutes:Int):Int {
		var localSecs = Math.ffloor(timeSecs) + utcOffsetMinutes * 60.0;
		var secsOfDay = localSecs - Math.ffloor(localSecs / 86400.0) * 86400.0;
		return Std.int(secsOfDay / 3600.0);
	}

	function zFor(hour:Int, ret:Float):Null<Float> {
		if (count[hour] < 2) return null;
		var variance = m2[hour] / (count[hour] - 1);
		if (variance > 0.0) return (ret - mean[hour]) / Math.sqrt(variance);
		return 0.0;
	}

	function accumulate(hour:Int, ret:Float):Void {
		count[hour]++;
		var delta = ret - mean[hour];
		mean[hour] += delta / count[hour];
		var delta2 = ret - mean[hour];
		m2[hour] += delta * delta2;
	}

	public function update(bar:Bar):Null<Float> {
		var hour = hourOf(bar.time, utcOffsetMinutes);
		var result:Null<Float> = null;
		if (prevClose != null) {
			var ret = prevClose == 0.0 ? 0.0 : bar.close / prevClose - 1.0;
			result = zFor(hour, ret);
			accumulate(hour, ret);
		}
		prevClose = bar.close;
		if (result != null) last = result;
		return result;
	}

	public function reset():Void {
		prevClose = null;
		count = [for (_ in 0...HOURS) 0];
		mean = [for (_ in 0...HOURS) 0.0];
		m2 = [for (_ in 0...HOURS) 0.0];
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "SeasonalZScore";

	public static function spec():IndicatorSpec {
		return {
			name: "seasonal_z_score", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var offset = IndicatorCache.intArg(args, 0, 0);
				return IndicatorCache.evalBar(h, "seasonal_z_score:" + offset, Math.NaN,
					() -> new SeasonalZScore(offset), (i, b) -> (cast i : SeasonalZScore).update(b));
			}
		};
	}
}
