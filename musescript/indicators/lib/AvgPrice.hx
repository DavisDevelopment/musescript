package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Average Price (AVGPRICE) — ported from wickra-core's `AvgPrice`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/avg_price.rs).
 *
 * The bar's `(open + high + low + close) / 4`. A per-bar price aggregate that
 * folds in all four OHLC prices. As a stateless transform, it emits a value
 * from the very first candle.
 */
class AvgPrice implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		return (bar.open + bar.high + bar.low + bar.close) / 4.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "AVGPRICE";

	public static function spec():IndicatorSpec {
		return {
			name: "avg_price", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "avg_price", Math.NaN,
				() -> new AvgPrice(), (i, b) -> (cast i : AvgPrice).update(b))
		};
	}
}
