package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Gravestone Doji candlestick pattern — a doji with a negligible lower
 * shadow and a long upper shadow, the mirror image of `DragonflyDoji`;
 * signals a potential bearish reversal (a failed push higher that fell back
 * to close near the open/low).
 *
 * tol = tolerance * (high - low)
 *
 * pattern (1.0) when:
 *  - body is negligible:      |close - open| <= tol
 *  - lower shadow negligible: (min(open, close) - low) <= tol
 *  - upper shadow dominant:   (high - max(open, close)) >= 0.6 * (high - low)
 *
 * 0.0 otherwise (including a zero-range bar).
 */
class GravestoneDoji implements MuseIndicator<Bar, Float> {
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

		if (body <= tol && lowerShadow <= tol && upperShadow >= 0.6 * range) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "GravestoneDoji";

	public static function spec():IndicatorSpec {
		return {
			name: "gravestone_doji", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "gravestone_doji:" + tol, Math.NaN,
					() -> new GravestoneDoji(tol), (i, b) -> (cast i : GravestoneDoji).update(b));
			}
		};
	}
}
