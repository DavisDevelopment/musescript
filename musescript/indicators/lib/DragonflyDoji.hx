package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Dragonfly Doji candlestick pattern — a doji with a negligible upper shadow
 * and a long lower shadow, signalling a potential bullish reversal (a
 * failed push lower that recovered to close near the open/high).
 *
 * tol = tolerance * (high - low)
 *
 * pattern (1.0) when:
 *  - body is negligible:      |close - open| <= tol
 *  - upper shadow negligible: (high - max(open, close)) <= tol
 *  - lower shadow dominant:   (min(open, close) - low) >= 0.6 * (high - low)
 *
 * 0.0 otherwise (including a zero-range bar).
 */
class DragonflyDoji implements MuseIndicator<Bar, Float> {
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

		var bodyTop = Math.max(bar.open, bar.close);
		var bodyBottom = Math.min(bar.open, bar.close);
		var body = bodyTop - bodyBottom;
		var upperShadow = bar.high - bodyTop;
		var lowerShadow = bodyBottom - bar.low;

		if (body <= tol && upperShadow <= tol && lowerShadow >= 0.6 * range) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "DragonflyDoji";

	public static function spec():IndicatorSpec {
		return {
			name: "dragonfly_doji", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "dragonfly_doji:" + tol, Math.NaN,
					() -> new DragonflyDoji(tol), (i, b) -> (cast i : DragonflyDoji).update(b));
			}
		};
	}
}
