package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Separating Lines candlestick pattern — a 2-bar continuation. After a
 * counter-trend candle, the next candle of the *opposite* colour opens right
 * back at the prior open and runs as an opening marubozu in the trend
 * direction.
 *
 * long body = |close - open| >= 0.5 * (high - low)
 * bar1, bar2 opposite colours
 * bar2 opens at bar1's open                 (|open2 - open1| <= 0.05 * range1)
 * bar2 is a long opening marubozu in its direction
 *   white bar2: open2 == low2  (no lower shadow)  -> +1.0
 *   black bar2: open2 == high2 (no upper shadow)  -> -1.0
 *
 * Output is 0.0 otherwise; the first bar always returns 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/separating_lines.rs
 */
class SeparatingLines implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = prev;
		prev = candle;
		if (bar1 == null) return 0.0;
		var range1 = bar1.high - bar1.low;
		var range2 = candle.high - candle.low;
		if (range1 <= 0.0 || range2 <= 0.0) return 0.0;
		// Opens must coincide.
		if (Math.abs(candle.open - bar1.open) > 0.05 * range1) return 0.0;
		var body2 = candle.close - candle.open;
		if (Math.abs(body2) < 0.5 * range2) return 0.0; // bar2 must be a long body
		var tol = 0.05 * range2;
		// Bullish: bar1 black, bar2 a long white opening marubozu (no lower wick).
		if (bar1.close < bar1.open && body2 > 0.0 && candle.open - candle.low <= tol) return 1.0;
		// Bearish: bar1 white, bar2 a long black opening marubozu (no upper wick).
		if (bar1.close > bar1.open && body2 < 0.0 && candle.high - candle.open <= tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "SeparatingLines";

	public static function spec():IndicatorSpec {
		return {
			name: "separating_lines", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "separating_lines", Math.NaN,
				() -> new SeparatingLines(), (i, b) -> (cast i : SeparatingLines).update(b))
		};
	}
}
