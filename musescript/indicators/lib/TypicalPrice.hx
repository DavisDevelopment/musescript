package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Typical Price — ported from wickra-core's `TypicalPrice`
 * (vendor/wickra/crates/wickra-core/src/indicators/typical_price.rs).
 *
 * The bar's `(high + low + close) / 3` — a single representative price per
 * bar that weights the close no more heavily than the two extremes. It is
 * the price series CCI and MFI are built on. As a stateless per-bar
 * transform it emits a value from the very first candle.
 */
class TypicalPrice implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		return (candle.high + candle.low + candle.close) / 3.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "TypicalPrice";

	public static function spec():IndicatorSpec {
		return {
			name: "typical_price", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "typical_price", Math.NaN,
				() -> new TypicalPrice(), (i, b) -> (cast i : TypicalPrice).update(b))
		};
	}
}
