package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Doji candlestick pattern — a single bar whose body is negligible relative
 * to its range (open and close nearly equal), signalling indecision.
 *
 * tol = tolerance * (high - low)
 * doji (1.0) when |close - open| <= tol; 0.0 otherwise (including a
 * zero-range bar, which carries no shape information).
 */
class Doji implements MuseIndicator<Bar, Float> {
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
		return Math.abs(bar.close - bar.open) <= tol ? 1.0 : 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Doji";

	public static function spec():IndicatorSpec {
		return {
			name: "doji", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "doji:" + tol, Math.NaN,
					() -> new Doji(tol), (i, b) -> (cast i : Doji).update(b));
			}
		};
	}
}
