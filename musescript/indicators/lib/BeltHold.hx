package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Belt Hold candlestick pattern — a single-bar reversal signal defined by a
 * long body opening at one extreme of the bar with little to no shadow on
 * that side.
 *
 * tol = tolerance * (high - low)
 *
 * bullish (+1.0): green body (close > open), opens within `tol` of the low
 *                 (negligible lower shadow), and the body is the dominant
 *                 part of the range (body >= 0.6 * range).
 * bearish (-1.0): red body (close < open), opens within `tol` of the high
 *                 (negligible upper shadow), body >= 0.6 * range.
 *
 * Output is 0.0 otherwise. Tolerance defaults to 5% of the bar's range.
 */
class BeltHold implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.05) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var range = bar.high - bar.low;
		if (range <= 0.0) return 0.0;

		var tol = tolerance * range;
		var body = Math.abs(bar.close - bar.open);
		if (body < 0.6 * range) return 0.0;

		if (bar.close > bar.open && (bar.open - bar.low) <= tol) return 1.0;
		if (bar.close < bar.open && (bar.high - bar.open) <= tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "BeltHold";

	public static function spec():IndicatorSpec {
		return {
			name: "belt_hold", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "belt_hold:" + tol, Math.NaN,
					() -> new BeltHold(tol), (i, b) -> (cast i : BeltHold).update(b));
			}
		};
	}
}
