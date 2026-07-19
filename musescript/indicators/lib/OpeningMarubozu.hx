package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Opening Marubozu candlestick pattern — a single-bar continuation signal
 * where price opens right at one extreme of the bar (no wick on the
 * opening side), the mirror of `ClosingMarubozu` (which constrains the
 * *close* side instead).
 *
 * tol = tolerance * (high - low)
 *
 * bullish (+1.0): green body (close > open), opens within `tol` of the low
 *                 (negligible lower shadow).
 * bearish (-1.0): red body (close < open), opens within `tol` of the high
 *                 (negligible upper shadow).
 *
 * Output is 0.0 otherwise (including a doji / zero-range bar).
 */
class OpeningMarubozu implements MuseIndicator<Bar, Float> {
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

		if (bar.close > bar.open && (bar.open - bar.low) <= tol) return 1.0;
		if (bar.close < bar.open && (bar.high - bar.open) <= tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "OpeningMarubozu";

	public static function spec():IndicatorSpec {
		return {
			name: "opening_marubozu", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "opening_marubozu:" + tol, Math.NaN,
					() -> new OpeningMarubozu(tol), (i, b) -> (cast i : OpeningMarubozu).update(b));
			}
		};
	}
}
