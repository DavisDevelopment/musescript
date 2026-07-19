package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.HilbertDominantCycle as HilbertDominantCyclePrim;
import musescript.types.MuseType;

/**
 * Builtin wrapper exposing the `prim/HilbertDominantCycle` Ehlers dominant
 * cycle estimator (already used internally by `AdaptiveCycle`) directly as
 * `hilbert_dominant_cycle(close)`. See prim/HilbertDominantCycle.hx for the
 * algorithm itself; this file only wires it into the builtin registry.
 */
class HilbertDominantCycle implements MuseIndicator<Float, Float> {
	var inner:HilbertDominantCyclePrim;

	public function new() {
		inner = new HilbertDominantCyclePrim();
	}

	public function update(input:Float):Null<Float> return inner.update(input);
	public function reset():Void inner.reset();
	public function warmupPeriod():Int return inner.warmupPeriod();
	public function isReady():Bool return inner.isReady();
	public function name():String return inner.name();

	public static function spec():IndicatorSpec {
		return {
			name: "hilbert_dominant_cycle", args: [TSeries], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "hilbert_dominant_cycle:" + series, series, Math.NaN,
					() -> new HilbertDominantCycle(), (i, v) -> (cast i : HilbertDominantCycle).update(v));
			}
		};
	}
}
