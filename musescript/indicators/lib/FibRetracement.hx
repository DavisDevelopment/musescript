package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Retracement output: the standard ratio levels between the window's high and low. */
typedef FibRetracementOutput = {
	var level0:Float;
	var level236:Float;
	var level382:Float;
	var level500:Float;
	var level618:Float;
	var level786:Float;
	var level1000:Float;
}

/**
 * Fibonacci Retracement: the standard retracement ladder between the
 * highest high and lowest low of the trailing `period` bars (current bar
 * included).
 *
 * range = highestHigh(period) - lowestLow(period)
 * level_r = lowestLow(period) + r * range,  for r in {0, .236, .382, .5, .618, .786, 1}
 *
 * `level0` sits at the window low, `level1000` at the window high; the rest
 * are the classic intermediate retracement ratios.
 */
class FibRetracement implements MuseIndicator<Bar, FibRetracementOutput> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "FibRetracement: period must be > 0";
		this.period = period;
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<FibRetracementOutput> {
		if (highs.length == period) highs.shift();
		highs.push(bar.high);
		if (lows.length == period) lows.shift();
		lows.push(bar.low);
		if (highs.length < period) return null;

		var hh = highs[0];
		for (v in highs) if (v > hh) hh = v;
		var ll = lows[0];
		for (v in lows) if (v < ll) ll = v;
		var range = hh - ll;

		return {
			level0: ll,
			level236: ll + 0.236 * range,
			level382: ll + 0.382 * range,
			level500: ll + 0.5 * range,
			level618: ll + 0.618 * range,
			level786: ll + 0.786 * range,
			level1000: hh
		};
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "FibRetracement";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_retracement", args: [TWindow], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level236", ty: TScalar}, {name: "level382", ty: TScalar},
				{name: "level500", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level786", ty: TScalar},
				{name: "level1000", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill = { level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN, level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN };
				return IndicatorCache.evalBar(h, "fib_retracement:" + p, nanFill,
					() -> new FibRetracement(p), (i, b) -> (cast i : FibRetracement).update(b));
			}
		};
	}
}
