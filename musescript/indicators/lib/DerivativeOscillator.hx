package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Rsi;
import musescript.indicators.prim.Ema;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Derivative Oscillator (Constance Brown): a double-smoothed RSI with a
 * signal line subtracted off, isolating RSI's own momentum the way MACD
 * isolates price's.
 *
 * rsi     = RSI(price, rsiPeriod)
 * smooth1 = EMA(rsi, ema1Period)
 * smooth2 = EMA(smooth1, ema2Period)
 * signal  = SMA(smooth2, signalPeriod)
 * DO      = smooth2 - signal
 */
class DerivativeOscillator implements MuseIndicator<Float, Float> {
	var rsi:Rsi;
	var ema1:Ema;
	var ema2:Ema;
	var signal:Sma;

	public function new(rsiPeriod:Int, ema1Period:Int, ema2Period:Int, signalPeriod:Int) {
		rsi = new Rsi(rsiPeriod);
		ema1 = new Ema(ema1Period);
		ema2 = new Ema(ema2Period);
		signal = new Sma(signalPeriod);
	}

	public function update(price:Float):Null<Float> {
		var r = rsi.update(price);
		if (r == null) return null;
		var s1 = ema1.update(r);
		if (s1 == null) return null;
		var s2 = ema2.update(s1);
		if (s2 == null) return null;
		var sig = signal.update(s2);
		if (sig == null) return null;
		return s2 - sig;
	}

	public function reset():Void {
		rsi.reset();
		ema1.reset();
		ema2.reset();
		signal.reset();
	}

	public function warmupPeriod():Int return rsi.warmupPeriod() + ema1.period + ema2.period + signal.period;
	public function isReady():Bool return signal.isReady();
	public function name():String return "DerivativeOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "derivative_oscillator", args: [TSeries, TWindow, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var rsiPeriod = IndicatorCache.intArg(args, 1, 14);
				var ema1Period = IndicatorCache.intArg(args, 2, 5);
				var ema2Period = IndicatorCache.intArg(args, 3, 3);
				var signalPeriod = IndicatorCache.intArg(args, 4, 9);
				var key = "derivative_oscillator:" + series + ":" + rsiPeriod + ":" + ema1Period + ":" + ema2Period + ":" + signalPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new DerivativeOscillator(rsiPeriod, ema1Period, ema2Period, signalPeriod), (i, v) -> (cast i : DerivativeOscillator).update(v));
			}
		};
	}
}
