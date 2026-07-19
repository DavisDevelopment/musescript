package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * PPO Histogram — ported from wickra-core's `PpoHistogram`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/ppo_histogram.rs).
 *
 * PPO Histogram is the ppo − signal bar of the Percentage Price Oscillator.
 * The signal line is a 9-period (or custom) EMA of the PPO line.
 */
class PpoHistogram implements MuseIndicator<Float, Float> {
	var ppo:Ppo;
	var signalEma:Ema;
	var signalPeriod:Int;
	var current:Null<Float>;

	public function new(fast:Int, slow:Int, signal:Int) {
		if (fast <= 0 || slow <= 0 || signal <= 0) throw "PpoHistogram: periods must be > 0";
		if (fast >= slow) throw "PpoHistogram: fast period must be < slow period";
		this.ppo = new Ppo(fast, slow);
		this.signalEma = new Ema(signal);
		this.signalPeriod = signal;
		this.current = null;
	}

	public function update(input:Float):Null<Float> {
		// Guard before touching either stage so a non-finite input never
		// advances the signal EMA on a stale, re-fed PPO value.
		if (!Math.isFinite(input)) {
			return current;
		}
		var ppoVal = ppo.update(input);
		if (ppoVal == null) return null;
		var signal = signalEma.update(ppoVal);
		if (signal == null) return null;
		var histogram = ppoVal - signal;
		current = histogram;
		return histogram;
	}

	public function reset():Void {
		ppo.reset();
		signalEma.reset();
		current = null;
	}

	public function warmupPeriod():Int {
		// Slow EMA seeds the PPO, then the signal EMA needs `signal − 1` more.
		return ppo.warmupPeriod() + signalPeriod - 1;
	}

	public function isReady():Bool return current != null;
	public function name():String return "PpoHistogram";

	public static function spec():IndicatorSpec {
		return {
			name: "ppo_histogram", args: [TWindow, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var f = IndicatorCache.intArg(args, 0, 12);
				var s = IndicatorCache.intArg(args, 1, 26);
				var sig = IndicatorCache.intArg(args, 2, 9);
				return IndicatorCache.evalSeries(h, "ppo_histogram:" + f + ":" + s + ":" + sig, "close", Math.NaN,
					() -> new PpoHistogram(f, s, sig), (i, v) -> (cast i : PpoHistogram).update(v));
			}
		};
	}
}
