package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Extension output: ratio levels projected beyond the window's high. */
typedef FibExtensionOutput = {
	var level0:Float;
	var level618:Float;
	var level1000:Float;
	var level1618:Float;
	var level2618:Float;
}

/**
 * Fibonacci Extension: projects the classic extension ratios beyond the
 * highest high of the trailing `period` bars, scaled by the window's range —
 * the levels traders watch for a breakout leg to travel toward.
 *
 * range = highestHigh(period) - lowestLow(period)
 * level_r = lowestLow(period) + r * range, for r in {0, .618, 1, 1.618, 2.618}
 *
 * `level1000` sits exactly at the window high; the ratios beyond it
 * (1.618, 2.618) are the actual "extension" targets past that high.
 */
class FibExtension implements MuseIndicator<Bar, FibExtensionOutput> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "FibExtension: period must be > 0";
		this.period = period;
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<FibExtensionOutput> {
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
			level618: ll + 0.618 * range,
			level1000: hh,
			level1618: ll + 1.618 * range,
			level2618: ll + 2.618 * range
		};
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "FibExtension";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_extension", args: [TWindow], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level1000", ty: TScalar},
				{name: "level1618", ty: TScalar}, {name: "level2618", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill = { level0: Math.NaN, level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN, level2618: Math.NaN };
				return IndicatorCache.evalBar(h, "fib_extension:" + p, nanFill,
					() -> new FibExtension(p), (i, b) -> (cast i : FibExtension).update(b));
			}
		};
	}
}
