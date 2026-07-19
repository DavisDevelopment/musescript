package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.HilbertDominantCycle;
import musescript.types.MuseType;

/**
 * Ehlers Adaptive Cycle period estimator — ported from wickra-core's `AdaptiveCycle`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adaptive_cycle.rs).
 *
 * Returns half the current dominant cycle period — the "best" lookback for
 * downstream oscillators like an adaptive RSI or adaptive Stochastic. The output
 * is rounded to an integer-valued `f64` and clamped to `[3, 25]`, matching the
 * typical operating range of period-adaptive oscillators.
 *
 * Series input (f64): called `adaptive_cycle(close)`, reading the chosen price series.
 */
class AdaptiveCycle implements MuseIndicator<Float, Float> {
	var cycle:HilbertDominantCycle;
	var lastValue:Null<Float>;

	public function new() {
		cycle = new HilbertDominantCycle();
		lastValue = null;
	}

	public function update(input:Float):Null<Float> {
		var period = cycle.update(input);
		if (period == null) return null;
		var half:Float = Math.round(period * 0.5);
		half = Math.max(half, 3.0);
		half = Math.min(half, 25.0);
		lastValue = half;
		return half;
	}

	public function reset():Void {
		cycle.reset();
		lastValue = null;
	}

	public function warmupPeriod():Int return cycle.warmupPeriod();
	public function isReady():Bool return lastValue != null;
	public function name():String return "AdaptiveCycle";

	/** Latest value, or NaN before ready. */
	public function value():Float return lastValue != null ? lastValue : Math.NaN;

	public static function spec():IndicatorSpec {
		return {
			name: "adaptive_cycle", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "adaptive_cycle:" + series, series, Math.NaN,
					() -> new AdaptiveCycle(), (i, v) -> (cast i : AdaptiveCycle).update(v));
			}
		};
	}
}
