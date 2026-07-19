package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Marubozu candlestick pattern — a full-body bar with no shadow on either
 * side at all (open at one extreme, close at the other).
 *
 * tol = tolerance * (high - low)
 *
 * bullish (+1.0): open within `tol` of low AND close within `tol` of high.
 * bearish (-1.0): open within `tol` of high AND close within `tol` of low.
 *
 * Output is 0.0 otherwise (including a zero-range bar).
 */
class Marubozu implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.02) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		var range = bar.high - bar.low;
		if (range <= 0.0) return 0.0;
		var tol = tolerance * range;

		if ((bar.open - bar.low) <= tol && (bar.high - bar.close) <= tol && bar.close > bar.open) return 1.0;
		if ((bar.high - bar.open) <= tol && (bar.close - bar.low) <= tol && bar.close < bar.open) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Marubozu";

	public static function spec():IndicatorSpec {
		return {
			name: "marubozu", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.02) : 0.02;
				return IndicatorCache.evalBar(h, "marubozu:" + tol, Math.NaN,
					() -> new Marubozu(tol), (i, b) -> (cast i : Marubozu).update(b));
			}
		};
	}
}
