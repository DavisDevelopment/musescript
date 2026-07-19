package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Minus Directional Indicator (TA-Lib `MINUS_DI`): the Wilder-smoothed
 * downward directional movement, normalized by Wilder-smoothed true range —
 * the -DI half of the same machinery `Adx`/`Dx` build the ADX line from,
 * exposed standalone.
 *
 * -DI = 100 * smoothedMinusDm / smoothedTrueRange
 */
class MinusDi implements MuseIndicator<Bar, Float> {
	var period:Int;
	var prev:Null<Bar>;
	var trSeed:Float;
	var dmSeed:Float;
	var seedCount:Int;
	var trSmooth:Null<Float>;
	var dmSmooth:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "MinusDi: period must be > 0";
		this.period = period;
		prev = null;
		trSeed = 0.0;
		dmSeed = 0.0;
		seedCount = 0;
		trSmooth = null;
		dmSmooth = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (prev == null) {
			prev = bar;
			return null;
		}
		var hl = bar.high - bar.low;
		var hc = Math.abs(bar.high - prev.close);
		var lc = Math.abs(bar.low - prev.close);
		var tr = Math.max(hl, Math.max(hc, lc));

		var up = bar.high - prev.high;
		var down = prev.low - bar.low;
		var minusDm = (down > up && down > 0.0) ? down : 0.0;
		prev = bar;

		var n:Float = period;
		var trV:Float, dmV:Float;
		if (trSmooth != null && dmSmooth != null) {
			trV = trSmooth - trSmooth / n + tr;
			dmV = dmSmooth - dmSmooth / n + minusDm;
			trSmooth = trV;
			dmSmooth = dmV;
		} else {
			trSeed += tr;
			dmSeed += minusDm;
			seedCount++;
			if (seedCount < period) return null;
			trSmooth = trSeed;
			dmSmooth = dmSeed;
			trV = trSeed;
			dmV = dmSeed;
		}
		return trV == 0.0 ? 0.0 : 100.0 * dmV / trV;
	}

	public function reset():Void {
		prev = null;
		trSeed = 0.0;
		dmSeed = 0.0;
		seedCount = 0;
		trSmooth = null;
		dmSmooth = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return trSmooth != null;
	public function name():String return "MinusDi";

	public static function spec():IndicatorSpec {
		return {
			name: "minus_di", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "minus_di:" + p, Math.NaN,
					() -> new MinusDi(p), (i, b) -> (cast i : MinusDi).update(b));
			}
		};
	}
}
