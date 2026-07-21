package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Piercing Line / Dark Cloud Cover candlestick pattern — a 2-bar reversal.
 *
 * Piercing Line (bullish, +1.0):
 *   prev red & curr green
 *     & curr.open < prev.low
 *     & curr.close > (prev.open + prev.close) / 2
 *     & curr.close < prev.open
 *
 * Dark Cloud Cover (bearish, -1.0):
 *   prev green & curr red
 *     & curr.open > prev.high
 *     & curr.close < (prev.open + prev.close) / 2
 *     & curr.close > prev.open
 *
 * Output is 0.0 otherwise; the first bar always returns 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/piercing_dark_cloud.rs
 */
class PiercingDarkCloud implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var p = prev;
		prev = candle;
		if (p == null) return 0.0;
		var prevRed = p.close < p.open;
		var prevGreen = p.close > p.open;
		var currGreen = candle.close > candle.open;
		var currRed = candle.close < candle.open;
		var mid = (p.open + p.close) / 2.0;
		if (prevRed
			&& currGreen
			&& candle.open < p.low
			&& candle.close > mid
			&& candle.close < p.open) {
			return 1.0;
		} else if (prevGreen
			&& currRed
			&& candle.open > p.high
			&& candle.close < mid
			&& candle.close > p.open) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "PiercingDarkCloud";

	public static function spec():IndicatorSpec {
		return {
			name: "piercing_dark_cloud", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "piercing_dark_cloud", Math.NaN,
				() -> new PiercingDarkCloud(), (i, b) -> (cast i : PiercingDarkCloud).update(b))
		};
	}
}
