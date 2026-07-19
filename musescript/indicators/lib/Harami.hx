package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Harami candlestick pattern — a 2-bar reversal where the second bar's body
 * is fully *contained inside* the first bar's body (the mirror image of
 * `Engulfing`, which requires the second bar to fully contain the first).
 *
 * bullish (+1.0): bar1 red with a real body, bar2 green, and bar2's body
 *                 lies entirely within bar1's body
 *                 (bar2.open >= bar1.close && bar2.close <= bar1.open).
 * bearish (-1.0): bar1 green with a real body, bar2 red, contained the
 *                 mirrored way (bar2.open <= bar1.close && bar2.close >= bar1.open).
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class Harami implements MuseIndicator<Bar, Float> {
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
		var body1 = Math.abs(bar1.close - bar1.open);
		if (body1 <= 0.0) return 0.0;

		var bar1Red = bar1.close < bar1.open;
		var bar1Green = bar1.close > bar1.open;
		var bar2Green = bar2.close > bar2.open;
		var bar2Red = bar2.close < bar2.open;

		if (bar1Red && bar2Green && bar2.open >= bar1.close && bar2.close <= bar1.open) return 1.0;
		if (bar1Green && bar2Red && bar2.open <= bar1.close && bar2.close >= bar1.open) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "Harami";

	public static function spec():IndicatorSpec {
		return {
			name: "harami", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "harami", Math.NaN,
				() -> new Harami(), (i, b) -> (cast i : Harami).update(b))
		};
	}
}
