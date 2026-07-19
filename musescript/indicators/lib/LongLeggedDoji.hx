package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Long-Legged Doji candlestick pattern — a doji (per `Doji`'s tighter
 * default tolerance) with substantial, roughly symmetric shadows on *both*
 * sides, distinguishing it from `HighWave` (which only requires both
 * shadows to be dominant, not necessarily balanced against each other).
 *
 * tol = tolerance * (high - low)
 *
 * pattern (1.0) when:
 *  - body negligible:        |close - open| <= tol
 *  - both shadows substantial: upperShadow >= 0.35*range AND lowerShadow >= 0.35*range
 *  - shadows roughly balanced: |upperShadow - lowerShadow| <= 0.3*range
 */
class LongLeggedDoji implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.03) {
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

		if (body <= tol
			&& upperShadow >= 0.35 * range
			&& lowerShadow >= 0.35 * range
			&& Math.abs(upperShadow - lowerShadow) <= 0.3 * range) {
			return 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "LongLeggedDoji";

	public static function spec():IndicatorSpec {
		return {
			name: "long_legged_doji", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.03) : 0.03;
				return IndicatorCache.evalBar(h, "long_legged_doji:" + tol, Math.NaN,
					() -> new LongLeggedDoji(tol), (i, b) -> (cast i : LongLeggedDoji).update(b));
			}
		};
	}
}
