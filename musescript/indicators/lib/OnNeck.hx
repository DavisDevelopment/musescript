package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * On Neck candlestick pattern — a weak 2-bar bearish continuation closely
 * related to `InNeck`, but the recovery bar closes at (rather than just
 * above) the *low* of the first bar instead of its close.
 *
 * tol = tolerance * bar1's body size
 *
 * bearish (-1.0) when:
 *  - bar1 red with a real body.
 *  - bar2 green, opens below bar1's low (gaps down).
 *  - bar2 closes within `tol` of bar1's low (the recovery stalls right at
 *    the prior low rather than reclaiming any of bar1's body).
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class OnNeck implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;

	public function new(tolerance:Float = 0.1) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	function compute(bar1:Bar, bar2:Bar):Float {
		var body1 = bar1.open - bar1.close;
		if (body1 <= 0.0) return 0.0;

		if (bar2.close <= bar2.open) return 0.0;
		if (bar2.open >= bar1.low) return 0.0;

		var tol = tolerance * body1;
		if (Math.abs(bar2.close - bar1.low) <= tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "OnNeck";

	public static function spec():IndicatorSpec {
		return {
			name: "on_neck", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.1) : 0.1;
				return IndicatorCache.evalBar(h, "on_neck:" + tol, Math.NaN,
					() -> new OnNeck(tol), (i, b) -> (cast i : OnNeck).update(b));
			}
		};
	}
}
