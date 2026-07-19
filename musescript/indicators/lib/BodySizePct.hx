package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Candle body size as a percentage of the bar's total range:
 *
 * BodySizePct = |close - open| / (high - low) * 100
 *
 * A stateless per-bar transform: 100 means the body fills the whole bar (no
 * wicks); a small value means most of the bar's range was wick. A zero-range
 * bar carries no shape information and reports 0.
 */
class BodySizePct implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var range = bar.high - bar.low;
		if (range <= 0.0) return 0.0;
		return Math.abs(bar.close - bar.open) / range * 100.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "BodySizePct";

	public static function spec():IndicatorSpec {
		return {
			name: "body_size_pct", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "body_size_pct", Math.NaN,
				() -> new BodySizePct(), (i, b) -> (cast i : BodySizePct).update(b))
		};
	}
}
