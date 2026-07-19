package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Percentage Price Oscillator — ported from wickra-core's `Ppo`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ppo.rs).
 *
 * PPO is the gap between a fast and a slow EMA, divided by the slow EMA and
 * scaled to a percentage: PPO = 100 · (EMA_fast − EMA_slow) / EMA_slow.
 * This makes PPO scale-free and comparable across assets.
 */
class Ppo implements MuseIndicator<Float, Float> {
	var fast:Int;
	var slow:Int;
	var emaFast:Ema;
	var emaSlow:Ema;
	var current:Null<Float>;

	public function new(fast:Int, slow:Int) {
		if (fast <= 0 || slow <= 0) throw "Ppo: periods must be > 0";
		if (fast >= slow) throw "Ppo: fast period must be < slow period";
		this.fast = fast;
		this.slow = slow;
		this.emaFast = new Ema(fast);
		this.emaSlow = new Ema(slow);
		this.current = null;
	}

	public function update(input:Float):Null<Float> {
		// Non-finite input is ignored; the EMAs are not advanced.
		if (!Math.isFinite(input)) {
			return current;
		}
		var f = emaFast.update(input);
		var s = emaSlow.update(input);
		if (f != null && s != null) {
			var ppo:Float;
			if (s == 0.0) {
				// Undefined ratio against a zero slow EMA: report flat.
				ppo = 0.0;
			} else {
				ppo = 100.0 * (f - s) / s;
			}
			current = ppo;
			return ppo;
		}
		return null;
	}

	public function reset():Void {
		emaFast.reset();
		emaSlow.reset();
		current = null;
	}

	public function warmupPeriod():Int return slow;
	public function isReady():Bool return current != null;
	public function name():String return "PPO";

	public static function spec():IndicatorSpec {
		return {
			name: "ppo", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var f = IndicatorCache.intArg(args, 0, 12);
				var s = IndicatorCache.intArg(args, 1, 26);
				return IndicatorCache.evalSeries(h, "ppo:" + f + ":" + s, "close", Math.NaN,
					() -> new Ppo(f, s), (i, v) -> (cast i : Ppo).update(v));
			}
		};
	}
}
