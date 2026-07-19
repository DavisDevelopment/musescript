package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Minus Directional Movement (TA-Lib `MINUS_DM`): the Wilder-smoothed raw
 * downward directional movement, *before* normalization by true range (see
 * `MinusDi` for the normalized -DI line, and `Adx`/`Dx` for the full
 * directional-movement family this shares its seeding/smoothing recurrence
 * with).
 *
 * minusDm_t = (prevLow - low_t)   if that exceeds the up-move and is
 *             positive, else 0
 * smoothed  = Wilder-smoothed sum of minusDm over `period` bars
 */
class MinusDm implements MuseIndicator<Bar, Float> {
	var period:Int;
	var prev:Null<Bar>;
	var seedSum:Float;
	var seedCount:Int;
	var smooth:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "MinusDm: period must be > 0";
		this.period = period;
		prev = null;
		seedSum = 0.0;
		seedCount = 0;
		smooth = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (prev == null) {
			prev = bar;
			return null;
		}
		var up = bar.high - prev.high;
		var down = prev.low - bar.low;
		var minusDm = (down > up && down > 0.0) ? down : 0.0;
		prev = bar;

		var n:Float = period;
		if (smooth != null) {
			smooth = smooth - smooth / n + minusDm;
			return smooth;
		}
		seedSum += minusDm;
		seedCount++;
		if (seedCount < period) return null;
		smooth = seedSum;
		return smooth;
	}

	public function reset():Void {
		prev = null;
		seedSum = 0.0;
		seedCount = 0;
		smooth = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return smooth != null;
	public function name():String return "MinusDm";

	public static function spec():IndicatorSpec {
		return {
			name: "minus_dm", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "minus_dm:" + p, Math.NaN,
					() -> new MinusDm(p), (i, b) -> (cast i : MinusDm).update(b));
			}
		};
	}
}
