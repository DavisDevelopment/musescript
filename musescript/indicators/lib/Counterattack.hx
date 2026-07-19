package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Counterattack (a.k.a. Meeting Lines) candlestick pattern — a 2-bar
 * reversal where a strong trend bar is met the next bar by an opposite-color
 * bar that gaps against the trend but closes back at almost the same level.
 *
 * tol = tolerance * bar1's body size
 *
 * bullish (+1.0): bar1 red, bar2 opens below bar1's close (gaps down,
 *                 continuing the downtrend) but is green and closes within
 *                 `tol` of bar1.close (the "counterattack" — the down move
 *                 is fully met and matched).
 * bearish (-1.0): bar1 green, bar2 opens above bar1's close (gaps up) but is
 *                 red and closes within `tol` of bar1.close.
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class Counterattack implements MuseIndicator<Bar, Float> {
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
		var body1 = Math.abs(bar1.close - bar1.open);
		if (body1 <= 0.0) return 0.0;
		var tol = tolerance * body1;
		var closesMatch = Math.abs(bar2.close - bar1.close) <= tol;

		if (bar1.close < bar1.open && bar2.open < bar1.close && bar2.close > bar2.open && closesMatch) return 1.0;
		if (bar1.close > bar1.open && bar2.open > bar1.close && bar2.close < bar2.open && closesMatch) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "Counterattack";

	public static function spec():IndicatorSpec {
		return {
			name: "counterattack", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.1) : 0.1;
				return IndicatorCache.evalBar(h, "counterattack:" + tol, Math.NaN,
					() -> new Counterattack(tol), (i, b) -> (cast i : Counterattack).update(b));
			}
		};
	}
}
