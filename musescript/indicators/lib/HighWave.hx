package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * High Wave candlestick pattern — an extreme-indecision bar with a
 * negligible body and long shadows on *both* sides (unlike `Doji`, which
 * only requires a small body regardless of shadow shape).
 *
 * tol = tolerance * (high - low)
 *
 * pattern (1.0) when:
 *  - body is negligible:  |close - open| <= tol
 *  - both shadows dominant: upperShadow >= 0.3*range AND lowerShadow >= 0.3*range
 *
 * 0.0 otherwise (including a zero-range bar).
 */
class HighWave implements MuseIndicator<Bar, Float> {
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

		if (body <= tol && upperShadow >= 0.3 * range && lowerShadow >= 0.3 * range) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "HighWave";

	public static function spec():IndicatorSpec {
		return {
			name: "high_wave", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "high_wave:" + tol, Math.NaN,
					() -> new HighWave(tol), (i, b) -> (cast i : HighWave).update(b));
			}
		};
	}
}
