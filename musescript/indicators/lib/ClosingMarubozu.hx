package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Closing Marubozu candlestick pattern — a single-bar continuation signal
 * where price closes right at one extreme of the bar (no wick on the
 * closing side), regardless of where it opened.
 *
 * tol = tolerance * (high - low)
 *
 * bullish (+1.0): green body (close > open), closes within `tol` of the high
 *                 (negligible upper shadow).
 * bearish (-1.0): red body (close < open), closes within `tol` of the low
 *                 (negligible lower shadow).
 *
 * Output is 0.0 otherwise (including a doji / zero-range bar). Tolerance
 * defaults to 5% of the bar's range. Unlike `BeltHold` (which constrains the
 * *open* side), this constrains the *close* side only.
 */
class ClosingMarubozu implements MuseIndicator<Bar, Float> {
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
		if (bar.close > bar.open && (bar.high - bar.close) <= tol) return 1.0;
		if (bar.close < bar.open && (bar.close - bar.low) <= tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ClosingMarubozu";

	public static function spec():IndicatorSpec {
		return {
			name: "closing_marubozu", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "closing_marubozu:" + tol, Math.NaN,
					() -> new ClosingMarubozu(tol), (i, b) -> (cast i : ClosingMarubozu).update(b));
			}
		};
	}
}
