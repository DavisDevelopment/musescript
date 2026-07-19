package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Harami Cross candlestick pattern — a `Harami` where the second bar is
 * specifically a doji, an even stronger indecision/reversal signal than a
 * generic small-bodied second bar.
 *
 * tol = tolerance * (bar2.high - bar2.low)
 *
 * bullish (+1.0): bar1 red with a real body, bar2 is a doji
 *                 (|close-open| <= tol) whose body lies within bar1's body.
 * bearish (-1.0): bar1 green with a real body, bar2 is a doji contained the
 *                 mirrored way.
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class HaramiCross implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;

	public function new(tolerance:Float = 0.05) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	function compute(bar1:Bar, bar2:Bar):Float {
		var body1 = Math.abs(bar1.close - bar1.open);
		if (body1 <= 0.0) return 0.0;

		var range2 = bar2.high - bar2.low;
		if (range2 <= 0.0) return 0.0;
		var bar2IsDoji = Math.abs(bar2.close - bar2.open) <= tolerance * range2;
		if (!bar2IsDoji) return 0.0;

		var bodyTop2 = Math.max(bar2.open, bar2.close);
		var bodyBottom2 = Math.min(bar2.open, bar2.close);

		var bar1Red = bar1.close < bar1.open;
		var bar1Green = bar1.close > bar1.open;

		// bar1 red: body range is [close, open]. bar1 green: body range is [open, close].
		if (bar1Red && bodyBottom2 >= bar1.close && bodyTop2 <= bar1.open) return 1.0;
		if (bar1Green && bodyBottom2 >= bar1.open && bodyTop2 <= bar1.close) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "HaramiCross";

	public static function spec():IndicatorSpec {
		return {
			name: "harami_cross", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "harami_cross:" + tol, Math.NaN,
					() -> new HaramiCross(tol), (i, b) -> (cast i : HaramiCross).update(b));
			}
		};
	}
}
