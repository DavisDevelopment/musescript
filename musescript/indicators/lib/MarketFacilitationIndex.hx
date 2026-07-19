package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Market Facilitation Index (Bill Williams): how efficiently a bar's volume
 * moved price — a stateless per-bar transform.
 *
 * MFI = (high - low) / volume
 *
 * Falls back to 0 on a zero-volume bar (undefined ratio).
 */
class MarketFacilitationIndex implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		if (bar.volume == 0.0) return 0.0;
		return (bar.high - bar.low) / bar.volume;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "MarketFacilitationIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "market_facilitation_index", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "market_facilitation_index", Math.NaN,
				() -> new MarketFacilitationIndex(), (i, b) -> (cast i : MarketFacilitationIndex).update(b))
		};
	}
}
