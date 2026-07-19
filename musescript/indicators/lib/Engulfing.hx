package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Engulfing candlestick pattern — a 2-bar reversal where the second bar's
 * body fully contains the first bar's body and is the opposite color.
 *
 * bullish (+1.0): bar1 red, bar2 green, bar2.open <= bar1.close and
 *                 bar2.close >= bar1.open (bar2's body engulfs bar1's).
 * bearish (-1.0): bar1 green, bar2 red, bar2.open >= bar1.close and
 *                 bar2.close <= bar1.open.
 *
 * Output is 0.0 otherwise (including the first bar, with no prior bar to
 * compare against).
 */
class Engulfing implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	static function compute(bar1:Bar, bar2:Bar):Float {
		var bar1Red = bar1.close < bar1.open;
		var bar1Green = bar1.close > bar1.open;
		var bar2Red = bar2.close < bar2.open;
		var bar2Green = bar2.close > bar2.open;

		if (bar1Red && bar2Green && bar2.open <= bar1.close && bar2.close >= bar1.open) return 1.0;
		if (bar1Green && bar2Red && bar2.open >= bar1.close && bar2.close <= bar1.open) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "Engulfing";

	public static function spec():IndicatorSpec {
		return {
			name: "engulfing", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "engulfing", Math.NaN,
				() -> new Engulfing(), (i, b) -> (cast i : Engulfing).update(b))
		};
	}
}
