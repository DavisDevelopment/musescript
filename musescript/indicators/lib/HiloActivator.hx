package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Hi-Lo Activator: a simple trend-following stop/reference line that
 * switches between an SMA of highs (while short/downtrending) and an SMA of
 * lows (while long/uptrending), flipping state when the close crosses the
 * opposite line.
 *
 * hiSma = SMA(high, period),  loSma = SMA(low, period)
 * while uptrending: line = loSma; flips to downtrend if close < hiSma
 * while downtrending: line = hiSma; flips to uptrend if close > loSma
 *
 * Starts in the uptrend state (a defensible, documented default — the first
 * emitted value has no prior trend to inherit).
 */
class HiloActivator implements MuseIndicator<Bar, Float> {
	var hiSma:Sma;
	var loSma:Sma;
	var uptrend:Bool;

	public function new(period:Int) {
		hiSma = new Sma(period);
		loSma = new Sma(period);
		uptrend = true;
	}

	public function update(bar:Bar):Null<Float> {
		var hi = hiSma.update(bar.high);
		var lo = loSma.update(bar.low);
		if (hi == null || lo == null) return null;

		if (uptrend) {
			if (bar.close < hi) uptrend = false;
		} else {
			if (bar.close > lo) uptrend = true;
		}
		return uptrend ? lo : hi;
	}

	public function reset():Void {
		hiSma.reset();
		loSma.reset();
		uptrend = true;
	}

	public function warmupPeriod():Int return hiSma.period;
	public function isReady():Bool return hiSma.isReady() && loSma.isReady();
	public function name():String return "HiloActivator";

	public static function spec():IndicatorSpec {
		return {
			name: "hilo_activator", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 13);
				return IndicatorCache.evalBar(h, "hilo_activator:" + p, Math.NaN,
					() -> new HiloActivator(p), (i, b) -> (cast i : HiloActivator).update(b));
			}
		};
	}
}
