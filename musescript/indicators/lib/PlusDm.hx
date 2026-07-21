package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Plus Directional Movement (TA-Lib `PLUS_DM`) — ported from wickra-core's
 * `PlusDm` (vendor/wickra/crates/wickra-core/src/indicators/plus_dm.rs): the
 * Wilder-smoothed raw upward directional movement, *before* normalization by
 * true range (see `PlusDi` for the normalized +DI line, and `Adx`/`Dx` for
 * the full directional-movement family this shares its seeding/smoothing
 * recurrence with).
 *
 * plusDm_t = (high_t - prevHigh)  if that exceeds the down-move and is
 *            positive, else 0
 * smoothed = Wilder-smoothed sum of plusDm over `period` bars
 */
class PlusDm implements MuseIndicator<Bar, Float> {
	var period:Int;
	var prev:Null<Bar>;
	var seedSum:Float;
	var seedCount:Int;
	var smooth:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "PlusDm: period must be > 0";
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
		var plusDm = (up > down && up > 0.0) ? up : 0.0;
		prev = bar;

		var n:Float = period;
		if (smooth != null) {
			smooth = smooth - smooth / n + plusDm;
			return smooth;
		}
		seedSum += plusDm;
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
	public function name():String return "PlusDm";

	public static function spec():IndicatorSpec {
		return {
			name: "plus_dm", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "plus_dm:" + p, Math.NaN,
					() -> new PlusDm(p), (i, b) -> (cast i : PlusDm).update(b));
			}
		};
	}
}
