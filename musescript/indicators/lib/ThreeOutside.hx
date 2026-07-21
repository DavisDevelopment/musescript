package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three Outside Up / Down candlestick pattern — a confirmed Engulfing: the
 * first two bars form an Engulfing pattern and the third bar confirms
 * direction.
 *
 * Three Outside Up (+1.0):
 *   1. Bar 1 is a red candle.
 *   2. Bar 2 is a green candle that engulfs Bar 1's body.
 *   3. Bar 3 is a green candle with close > b2.close.
 *
 * Three Outside Down (-1.0): the mirror — green, bearish engulfing, followed
 * by a red bar closing below Bar 2's close.
 *
 * Output is 0.0 otherwise; the first two bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/three_outside.rs
 */
class ThreeOutside implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var b1 = prevPrev;
		var b2 = prev;
		prevPrev = prev;
		prev = candle;
		if (b1 == null || b2 == null) return 0.0;
		var body1 = Math.abs(b1.close - b1.open);
		var body2 = Math.abs(b2.close - b2.open);
		if (body1 <= 0.0 || body2 <= body1) return 0.0;
		var b1Red = b1.close < b1.open;
		var b1Green = b1.close > b1.open;
		var b2Green = b2.close > b2.open;
		var b2Red = b2.close < b2.open;
		var b3Green = candle.close > candle.open;
		var b3Red = candle.close < candle.open;
		// Bullish: prior red, engulfing green (b2 fully engulfs b1 body), then green confirms above b2.close.
		if (b1Red
			&& b2Green
			&& b2.open <= b1.close
			&& b2.close >= b1.open
			&& b3Green
			&& candle.close > b2.close) {
			return 1.0;
		}
		// Bearish: prior green, engulfing red, then red confirms below b2.close.
		if (b1Green
			&& b2Red
			&& b2.open >= b1.close
			&& b2.close <= b1.open
			&& b3Red
			&& candle.close < b2.close) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ThreeOutside";

	public static function spec():IndicatorSpec {
		return {
			name: "three_outside", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "three_outside", Math.NaN,
				() -> new ThreeOutside(), (i, b) -> (cast i : ThreeOutside).update(b))
		};
	}
}
