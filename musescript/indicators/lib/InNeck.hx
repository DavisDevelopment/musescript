package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * In Neck candlestick pattern — a weak 2-bar bearish continuation: a long
 * red bar followed by a green bar that gaps down but claws back to close at
 * (or barely above) the first bar's close, "in the neck" of the prior move.
 *
 * tol = tolerance * bar1's body size
 *
 * bearish (-1.0) when:
 *  - bar1 red with a real body.
 *  - bar2 green, opens below bar1's low (gaps down).
 *  - bar2 closes within `tol` of bar1's close, at or only slightly above it
 *    (bar2.close >= bar1.close), i.e. the recovery barely reaches the prior
 *    close rather than piercing meaningfully into bar1's body.
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class InNeck implements MuseIndicator<Bar, Float> {
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
		if (body1 <= 0.0) return 0.0; // bar1 must be red

		if (bar2.close <= bar2.open) return 0.0; // bar2 must be green
		if (bar2.open >= bar1.low) return 0.0; // must gap below bar1's low

		var tol = tolerance * body1;
		if (bar2.close >= bar1.close && bar2.close <= bar1.close + tol) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "InNeck";

	public static function spec():IndicatorSpec {
		return {
			name: "in_neck", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.1) : 0.1;
				return IndicatorCache.evalBar(h, "in_neck:" + tol, Math.NaN,
					() -> new InNeck(tol), (i, b) -> (cast i : InNeck).update(b));
			}
		};
	}
}
