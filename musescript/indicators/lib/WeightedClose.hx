package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Weighted Close — ported from wickra-core's `WeightedClose`
 * (vendor/wickra/crates/wickra-core/src/indicators/weighted_close.rs).
 *
 * The bar's `(high + low + 2·close) / 4` — a representative per-bar price
 * that, unlike the Typical Price, gives the close double weight. As a
 * stateless per-bar transform it emits a value from the very first candle.
 */
class WeightedClose implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		return (candle.high + candle.low + 2.0 * candle.close) / 4.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "WeightedClose";

	public static function spec():IndicatorSpec {
		return {
			name: "weighted_close", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "weighted_close", Math.NaN,
				() -> new WeightedClose(), (i, b) -> (cast i : WeightedClose).update(b))
		};
	}
}
