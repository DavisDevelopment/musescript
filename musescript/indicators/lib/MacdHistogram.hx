package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * MACD Histogram: the classic MACD line minus its own signal EMA, exposed
 * as a standalone oscillator (rather than bundled with the MACD/signal
 * lines themselves).
 *
 * macd   = EMA(price, fast) - EMA(price, slow)
 * signal = EMA(macd, signalPeriod)
 * hist   = macd - signal
 */
class MacdHistogram implements MuseIndicator<Float, Float> {
	var fastEma:Ema;
	var slowEma:Ema;
	var signalEma:Ema;

	public function new(fast:Int, slow:Int, signalPeriod:Int) {
		if (fast >= slow) throw "MacdHistogram: fast period must be strictly less than slow";
		fastEma = new Ema(fast);
		slowEma = new Ema(slow);
		signalEma = new Ema(signalPeriod);
	}

	public function update(price:Float):Null<Float> {
		var f = fastEma.update(price);
		var s = slowEma.update(price);
		if (f == null || s == null) return null;
		var macd = f - s;
		var sig = signalEma.update(macd);
		if (sig == null) return null;
		return macd - sig;
	}

	public function reset():Void {
		fastEma.reset();
		slowEma.reset();
		signalEma.reset();
	}

	public function warmupPeriod():Int return slowEma.period + signalEma.period;
	public function isReady():Bool return signalEma.isReady();
	public function name():String return "MacdHistogram";

	public static function spec():IndicatorSpec {
		return {
			name: "macd_histogram", args: [TSeries, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fast = IndicatorCache.intArg(args, 1, 12);
				var slow = IndicatorCache.intArg(args, 2, 26);
				var signalPeriod = IndicatorCache.intArg(args, 3, 9);
				var key = "macd_histogram:" + series + ":" + fast + ":" + slow + ":" + signalPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new MacdHistogram(fast, slow, signalPeriod), (i, v) -> (cast i : MacdHistogram).update(v));
			}
		};
	}
}
