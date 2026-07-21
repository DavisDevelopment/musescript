package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Breakaway — a 5-bar reversal pattern. A trend gaps away on the second bar,
 * drifts two more bars in the same direction, then the fifth bar snaps the
 * other way and closes back inside the body gap left between the first and
 * second bars, signalling the move has broken away from the crowd and is
 * turning.
 *
 * Ported from wickra-core's `Breakaway`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/breakaway.rs).
 *
 * Output is `+1.0` bullish, `−1.0` bearish, `0.0` otherwise. The first four
 * bars always return `0.0` because the five-bar window is not yet filled.
 * Pattern-shape check only — no trend filter is applied.
 */
class Breakaway implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var c3:Null<Bar>;
	var c4:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = c1;
		var bar2 = c2;
		var bar3 = c3;
		var bar4 = c4;
		c1 = c2;
		c2 = c3;
		c3 = c4;
		c4 = candle;

		// If we don't have all 5 bars yet, return 0.0
		if (bar1 == null || bar2 == null || bar3 == null || bar4 == null) {
			return 0.0;
		}

		// Bullish: a decline gaps lower, runs two more bars down, then a green
		// bar5 closes back inside the bar1/bar2 body gap.
		if (bar1.close < bar1.open
			&& bar2.close < bar2.open
			&& bar2.open < bar1.close
			&& bar3.high < bar2.high
			&& bar3.low < bar2.low
			&& bar4.close < bar4.open
			&& bar4.high < bar3.high
			&& bar4.low < bar3.low
			&& candle.close > candle.open
			&& candle.close > bar2.open
			&& candle.close < bar1.close) {
			return 1.0;
		}

		// Bearish: the mirror — an advance gaps higher, runs two more bars up,
		// then a red bar5 closes back inside the bar1/bar2 body gap.
		if (bar1.close > bar1.open
			&& bar2.close > bar2.open
			&& bar2.open > bar1.close
			&& bar3.high > bar2.high
			&& bar3.low > bar2.low
			&& bar4.close > bar4.open
			&& bar4.high > bar3.high
			&& bar4.low > bar3.low
			&& candle.close < candle.open
			&& candle.close < bar2.open
			&& candle.close > bar1.close) {
			return -1.0;
		}

		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Breakaway";

	public static function spec():IndicatorSpec {
		return {
			name: "breakaway", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				return IndicatorCache.evalBar(h, "breakaway", Math.NaN,
					() -> new Breakaway(), (i, b) -> (cast i : Breakaway).update(b));
			}
		};
	}
}
