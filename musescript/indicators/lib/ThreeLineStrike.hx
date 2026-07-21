package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three Line Strike candlestick pattern — a 4-bar pattern: three candles
 * marching in one direction (a three-soldiers / three-crows advance)
 * followed by a fourth candle of the opposite colour that opens beyond the
 * third candle and closes back past the first candle's open, "striking"
 * through the whole run.
 *
 * Bullish (+1.0):
 *   bar1..bar3 green, each opening inside the prior body and closing higher
 *   bar4 red & opens above bar3's close & closes below bar1's open
 *
 * Bearish (-1.0): the mirror — three falling red candles struck by a green
 * bar4 that opens below bar3's close and closes above bar1's open.
 *
 * Output is 0.0 otherwise; the first three bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/three_line_strike.rs
 */
class ThreeLineStrike implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var c3:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		c3 = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = c1;
		var bar2 = c2;
		var bar3 = c3;
		c1 = c2;
		c2 = c3;
		c3 = candle;
		if (bar1 == null || bar2 == null || bar3 == null) return 0.0;
		// Bullish: three rising green candles struck by a red bar4.
		if (bar1.close > bar1.open
			&& bar2.close > bar2.open
			&& bar3.close > bar3.open
			&& bar2.open >= bar1.open
			&& bar2.open <= bar1.close
			&& bar2.close > bar1.close
			&& bar3.open >= bar2.open
			&& bar3.open <= bar2.close
			&& bar3.close > bar2.close
			&& candle.close < candle.open
			&& candle.open > bar3.close
			&& candle.close < bar1.open) {
			return 1.0;
		}
		// Bearish: three falling red candles struck by a green bar4.
		if (bar1.close < bar1.open
			&& bar2.close < bar2.open
			&& bar3.close < bar3.open
			&& bar2.open <= bar1.open
			&& bar2.open >= bar1.close
			&& bar2.close < bar1.close
			&& bar3.open <= bar2.open
			&& bar3.open >= bar2.close
			&& bar3.close < bar2.close
			&& candle.close > candle.open
			&& candle.open < bar3.close
			&& candle.close > bar1.open) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		c3 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 4;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ThreeLineStrike";

	public static function spec():IndicatorSpec {
		return {
			name: "three_line_strike", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "three_line_strike", Math.NaN,
				() -> new ThreeLineStrike(), (i, b) -> (cast i : ThreeLineStrike).update(b))
		};
	}
}
