package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Abandoned Baby candlestick pattern — ported from wickra-core's `AbandonedBaby`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/abandoned_baby.rs).
 *
 * A strong 3-bar reversal where a doji is "abandoned" by price gaps on both sides,
 * isolating it from the candles before and after.
 *
 * tol           = tolerance * max(|bar2.open|, |bar2.close|)
 * bar2 doji                                   (|bar2.close − bar2.open| <= tol)
 *
 * bullish  (+1.0): bar1 red, bar2 gaps fully below bar1 (bar2.high < bar1.low),
 *                  bar3 green and gaps fully above bar2 (bar3.low > bar2.high)
 * bearish  (−1.0): bar1 green, bar2 gaps fully above bar1 (bar2.low > bar1.high),
 *                  bar3 red and gaps fully below bar2 (bar3.high < bar2.low)
 *
 * Output is 0.0 otherwise. Tolerance defaults to 0.001 (10 bps relative).
 */
class AbandonedBaby implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.001) {
		// Clamp tolerance to valid range [0, 1) to be lenient with invalid inputs
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp == null || p == null) {
			return 0.0;
		}

		var bar1 = pp;
		var bar2 = p;
		var bar3 = bar;

		var tol = tolerance * Math.max(Math.abs(bar2.open), Math.abs(bar2.close));
		var bar2IsDoji = Math.abs(bar2.close - bar2.open) <= tol;

		if (!bar2IsDoji) {
			return 0.0;
		}

		// Bullish: red bar1, doji gaps below, green bar3 gaps above.
		if (bar1.close < bar1.open
			&& bar2.high < bar1.low
			&& bar3.close > bar3.open
			&& bar3.low > bar2.high) {
			return 1.0;
		}

		// Bearish: green bar1, doji gaps above, red bar3 gaps below.
		if (bar1.close > bar1.open
			&& bar2.low > bar1.high
			&& bar3.close < bar3.open
			&& bar3.high < bar2.low) {
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
	public function name():String return "AbandonedBaby";

	public static function spec():IndicatorSpec {
		return {
			name: "abandoned_baby", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.001) : 0.001;
				return IndicatorCache.evalBar(h, "abandoned_baby:" + tol, Math.NaN,
					() -> new AbandonedBaby(tol), (i, b) -> (cast i : AbandonedBaby).update(b));
			}
		};
	}
}
