package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Decycler Oscillator (Ehlers): the percentage spread between two
 * `Decycler` trend lines at different cutoff periods — a smooth,
 * low-lag alternative to a MACD-style oscillator.
 *
 * DecOsc = 100 * (decycler(price, fastPeriod) - decycler(price, slowPeriod)) / price
 *
 * Positive means the faster (shorter-cutoff) decycler sits above the slower
 * one — the underlying trend has recently turned up; negative means down.
 */
class DecyclerOscillator implements MuseIndicator<Float, Float> {
	var fast:Decycler;
	var slow:Decycler;
	var lastPrice:Null<Float>;

	public function new(fastPeriod:Int, slowPeriod:Int) {
		fast = new Decycler(fastPeriod);
		slow = new Decycler(slowPeriod);
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		var f = fast.update(price);
		var s = slow.update(price);
		lastPrice = price;
		if (f == null || s == null) return null;
		if (price == 0.0) return 0.0;
		return 100.0 * (f - s) / price;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
		lastPrice = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return fast.isReady() && slow.isReady();
	public function name():String return "DecyclerOscillator";

	public static function spec():IndicatorSpec {
		return {
			name: "decycler_oscillator", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fastPeriod = IndicatorCache.intArg(args, 1, 10);
				var slowPeriod = IndicatorCache.intArg(args, 2, 30);
				var key = "decycler_oscillator:" + series + ":" + fastPeriod + ":" + slowPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new DecyclerOscillator(fastPeriod, slowPeriod), (i, v) -> (cast i : DecyclerOscillator).update(v));
			}
		};
	}
}
