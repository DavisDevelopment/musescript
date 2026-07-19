package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Doji Star candlestick pattern — a 2-bar reversal where a normal-bodied
 * candle is followed by a gapping doji, isolated from the trend by the gap.
 *
 * tol = tolerance * (bar2.high - bar2.low)
 *
 * bullish (+1.0): bar1 red with a real body, bar2 is a doji
 *                 (|close-open| <= tol) that gapped down
 *                 (bar2.high < bar1.close).
 * bearish (-1.0): bar1 green with a real body, bar2 is a doji that gapped up
 *                 (bar2.low > bar1.close).
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class DojiStar implements MuseIndicator<Bar, Float> {
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
		var range2 = bar2.high - bar2.low;
		if (range2 <= 0.0) return 0.0;
		var tol = tolerance * range2;
		var bar2IsDoji = Math.abs(bar2.close - bar2.open) <= tol;
		if (!bar2IsDoji) return 0.0;

		if (bar1.close < bar1.open && bar2.high < bar1.close) return 1.0;
		if (bar1.close > bar1.open && bar2.low > bar1.close) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "DojiStar";

	public static function spec():IndicatorSpec {
		return {
			name: "doji_star", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "doji_star:" + tol, Math.NaN,
					() -> new DojiStar(tol), (i, b) -> (cast i : DojiStar).update(b));
			}
		};
	}
}
