package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three Stars in the South candlestick pattern — ported from wickra-core's
 * `ThreeStarsInSouth`
 * (vendor/wickra/crates/wickra-core/src/indicators/three_stars_in_south.rs).
 *
 * A rare 3-bar bullish reversal: three shrinking red candles where each
 * session carves out a higher low and contracts toward a tiny black
 * marubozu, signalling exhausted selling at the bottom of a decline.
 *
 *   tol = tolerance * max(|bar3.high|, |bar3.low|)
 *   all three red                                       (close < open)
 *   bar1 long lower shadow  (bar1.close − bar1.low) >= (bar1.open − bar1.close)
 *   bar2 opens inside bar1's body, higher low, smaller body, closes above bar1.close
 *   bar3 small black marubozu (upper & lower shadow <= tol) inside bar2's range
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only;
 * never emits −1.0). The first two bars always return 0.0. `tolerance`
 * defaults to 0.001 and must lie in [0, 1).
 */
class ThreeStarsInSouth implements MuseIndicator<Bar, Float> {
	var toleranceValue:Float;
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.001) {
		if (!(tolerance >= 0.0 && tolerance < 1.0))
			throw "ThreeStarsInSouth: tolerance must be in [0, 1)";
		this.toleranceValue = tolerance;
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	/** Configured relative tolerance. */
	public function tolerance():Float return toleranceValue;

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = prevPrev;
		var bar2 = prev;
		prevPrev = prev;
		prev = candle;
		if (bar1 == null || bar2 == null) return 0.0;
		var tol = toleranceValue * Math.max(Math.abs(candle.high), Math.abs(candle.low));
		var bar1Body = bar1.open - bar1.close;
		var bar1LowerShadow = bar1.close - bar1.low;
		var bar2Body = bar2.open - bar2.close;
		var bar3UpperShadow = candle.high - candle.open;
		var bar3LowerShadow = candle.close - candle.low;
		if (bar1.close < bar1.open
			&& bar2.close < bar2.open
			&& candle.close < candle.open
			&& bar1LowerShadow >= bar1Body
			&& bar2.open <= bar1.open
			&& bar2.open >= bar1.close
			&& bar2.low > bar1.low
			&& bar2.close > bar1.close
			&& bar2Body < bar1Body
			&& bar3UpperShadow <= tol
			&& bar3LowerShadow <= tol
			&& candle.high < bar2.high
			&& candle.low > bar2.low) {
			return 1.0;
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
	public function name():String return "ThreeStarsInSouth";

	public static function spec():IndicatorSpec {
		return {
			name: "three_stars_in_south", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = IndicatorCache.floatArg(args, 0, 0.001);
				return IndicatorCache.evalBar(h, "three_stars_in_south:" + tol, Math.NaN,
					() -> new ThreeStarsInSouth(tol), (i, b) -> (cast i : ThreeStarsInSouth).update(b));
			}
		};
	}
}
