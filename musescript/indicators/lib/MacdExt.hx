package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/** MACD Ext output: the macd line, its signal line, and their spread. */
typedef MacdExtOutput = {
	var macd:Float;
	var signal:Float;
	var histogram:Float;
}

/**
 * MACD Extended: the full three-line MACD output (macd, signal, histogram)
 * with fully configurable fast/slow/signal periods — the "extended" TA-Lib
 * `MACDEXT` counterpart to the plain `MacdHistogram` scalar oscillator.
 */
class MacdExt implements MuseIndicator<Float, MacdExtOutput> {
	var fastEma:Ema;
	var slowEma:Ema;
	var signalEma:Ema;

	public function new(fast:Int, slow:Int, signalPeriod:Int) {
		if (fast >= slow) throw "MacdExt: fast period must be strictly less than slow";
		fastEma = new Ema(fast);
		slowEma = new Ema(slow);
		signalEma = new Ema(signalPeriod);
	}

	public function update(price:Float):Null<MacdExtOutput> {
		var f = fastEma.update(price);
		var s = slowEma.update(price);
		if (f == null || s == null) return null;
		var macd = f - s;
		var sig = signalEma.update(macd);
		if (sig == null) return null;
		return { macd: macd, signal: sig, histogram: macd - sig };
	}

	public function reset():Void {
		fastEma.reset();
		slowEma.reset();
		signalEma.reset();
	}

	public function warmupPeriod():Int return slowEma.period + signalEma.period;
	public function isReady():Bool return signalEma.isReady();
	public function name():String return "MacdExt";

	public static function spec():IndicatorSpec {
		return {
			name: "macd_ext", args: [TSeries, TWindow, TWindow, TWindow], ret: TObject([
				{name: "macd", ty: TScalar}, {name: "signal", ty: TScalar}, {name: "histogram", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fast = IndicatorCache.intArg(args, 1, 12);
				var slow = IndicatorCache.intArg(args, 2, 26);
				var signalPeriod = IndicatorCache.intArg(args, 3, 9);
				var key = "macd_ext:" + series + ":" + fast + ":" + slow + ":" + signalPeriod;
				var nanFill = { macd: Math.NaN, signal: Math.NaN, histogram: Math.NaN };
				return IndicatorCache.evalSeries(h, key, series, nanFill,
					() -> new MacdExt(fast, slow, signalPeriod), (i, v) -> (cast i : MacdExt).update(v));
			}
		};
	}
}
