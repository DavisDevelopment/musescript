package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Klinger Volume Oscillator: a volume-force oscillator that tracks whether
 * volume is confirming the direction of the typical-price trend.
 *
 * typicalPrice_t = (high + low + close) / 3
 * trend_t        = +1 if typicalPrice_t > typicalPrice_{t-1}, -1 if <, else
 *                  holds the previous trend (first bar: +1)
 * dm_t           = high_t - low_t
 * cm_t           = dm_t + (trend unchanged from previous bar
 *                          ? cm_{t-1}
 *                          : dm_{t-1})                (Klinger's cumulative
 *                                                       measure, reset at
 *                                                       each trend flip)
 * vf_t           = volume_t * |2*(dm_t/cm_t - 1)| * trend_t * 100
 * KVO            = EMA(vf, fastPeriod) - EMA(vf, slowPeriod)
 */
class Kvo implements MuseIndicator<Bar, Float> {
	var fastEma:Ema;
	var slowEma:Ema;
	var hasPrev:Bool;
	var prevTypical:Float;
	var prevDm:Float;
	var cm:Float;
	var trend:Float;

	public function new(fastPeriod:Int, slowPeriod:Int) {
		if (fastPeriod >= slowPeriod) throw "Kvo: fastPeriod must be strictly less than slowPeriod";
		fastEma = new Ema(fastPeriod);
		slowEma = new Ema(slowPeriod);
		hasPrev = false;
		prevTypical = 0.0;
		prevDm = 0.0;
		cm = 0.0;
		trend = 1.0;
	}

	public function update(bar:Bar):Null<Float> {
		var typical = (bar.high + bar.low + bar.close) / 3.0;
		var dm = bar.high - bar.low;

		if (!hasPrev) {
			cm = dm;
			prevTypical = typical;
			prevDm = dm;
			hasPrev = true;
			return null;
		}

		var newTrend = typical > prevTypical ? 1.0 : (typical < prevTypical ? -1.0 : trend);
		cm = newTrend == trend ? cm + dm : prevDm + dm;
		trend = newTrend;

		var vf = cm == 0.0 ? 0.0 : bar.volume * Math.abs(2.0 * (dm / cm - 1.0)) * trend * 100.0;

		prevTypical = typical;
		prevDm = dm;

		var f = fastEma.update(vf);
		var s = slowEma.update(vf);
		if (f == null || s == null) return null;
		return f - s;
	}

	public function reset():Void {
		fastEma.reset();
		slowEma.reset();
		hasPrev = false;
		prevTypical = 0.0;
		prevDm = 0.0;
		cm = 0.0;
		trend = 1.0;
	}

	public function warmupPeriod():Int return slowEma.period + 1;
	public function isReady():Bool return slowEma.isReady();
	public function name():String return "Kvo";

	public static function spec():IndicatorSpec {
		return {
			name: "kvo", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var fast = IndicatorCache.intArg(args, 0, 34);
				var slow = IndicatorCache.intArg(args, 1, 55);
				var key = "kvo:" + fast + ":" + slow;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new Kvo(fast, slow), (i, b) -> (cast i : Kvo).update(b));
			}
		};
	}
}
