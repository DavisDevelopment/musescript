package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Chaikin Oscillator: the MACD-style spread between a fast and slow EMA of
 * the Accumulation/Distribution Line (see `Adl`).
 *
 * ChaikinOsc = EMA(ADL, fast) - EMA(ADL, slow)
 *
 * Momentum of money flow: rising when accumulation is accelerating, falling
 * when distribution is accelerating.
 */
class ChaikinOscillator implements MuseIndicator<Bar, Float> {
	var adl:Adl;
	var fastEma:Ema;
	var slowEma:Ema;

	public function new(fast:Int, slow:Int) {
		if (fast <= 0 || slow <= 0) throw "ChaikinOscillator: periods must be > 0";
		if (fast >= slow) throw "ChaikinOscillator: fast period must be strictly less than slow";
		adl = new Adl();
		fastEma = new Ema(fast);
		slowEma = new Ema(slow);
	}

	public function update(bar:Bar):Null<Float> {
		var a = adl.update(bar);
		var f = fastEma.update(a);
		var s = slowEma.update(a);
		if (f == null || s == null) return null;
		return f - s;
	}

	public function reset():Void {
		adl.reset();
		fastEma.reset();
		slowEma.reset();
	}

	public function warmupPeriod():Int return slowEma.period;
	public function isReady():Bool return slowEma.isReady();
	public function name():String return "ChaikinOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "chaikin_oscillator", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var fast = IndicatorCache.intArg(args, 0, 3);
				var slow = IndicatorCache.intArg(args, 1, 10);
				var key = "chaikin_oscillator:" + fast + ":" + slow;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new ChaikinOscillator(fast, slow), (i, b) -> (cast i : ChaikinOscillator).update(b));
			}
		};
	}
}
