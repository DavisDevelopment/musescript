package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Single Prints — ported from wickra-core's `SinglePrints`
 * (vendor/wickra/crates/wickra-core/src/indicators/single_prints.rs).
 *
 * The number of price levels (bins) in the rolling profile that were
 * touched by exactly one bar, marking zones of low acceptance / fast
 * movement. For each of `bins` price levels over the last `period` candles,
 * `touches` is the number of bars whose high-low range covers that level;
 * the output is the count of levels with `touches == 1`. A window with zero
 * high-low span yields `0`. The first value lands after `period` candles.
 */
class SinglePrints implements MuseIndicator<Bar, Float> {
	var period:Int;
	var bins:Int;
	var window:Array<Bar>;
	var last:Null<Float>;

	public function new(period:Int, bins:Int) {
		if (period <= 0 || bins <= 0) throw "SinglePrints: period and bins must be > 0";
		this.period = period;
		this.bins = bins;
		this.window = [];
		this.last = null;
	}

	/** Configured `(period, bins)`. */
	public function params():{period:Int, bins:Int} {
		return {period: period, bins: bins};
	}

	/** Current value if available. */
	public function value():Null<Float> return last;

	function countSinglePrints():Int {
		var low = Math.POSITIVE_INFINITY;
		var high = Math.NEGATIVE_INFINITY;
		for (c in window) {
			if (c.low < low) low = c.low;
			if (c.high > high) high = c.high;
		}
		var span = high - low;
		if (span <= 0.0) return 0;
		var width = span / bins;
		var touches = [for (_ in 0...bins) 0];
		for (c in window) {
			var loIdx = clampBin(Math.ffloor((c.low - low) / width));
			var hiIdx = clampBin(Math.ffloor((c.high - low) / width));
			for (t in loIdx...(hiIdx + 1)) {
				touches[t] += 1;
			}
		}
		var count = 0;
		for (t in touches) {
			if (t == 1) count++;
		}
		return count;
	}

	inline function clampBin(raw:Float):Int {
		var idx = Std.int(raw);
		return idx < bins - 1 ? idx : bins - 1;
	}

	public function update(bar:Bar):Null<Float> {
		if (window.length == period) window.shift();
		window.push(bar);
		if (window.length < period) return null;
		var count:Float = countSinglePrints();
		last = count;
		return count;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "SinglePrints";

	public static function spec():IndicatorSpec {
		return {
			name: "single_prints", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 24);
				return IndicatorCache.evalBar(h, "single_prints:" + p + ":" + b, Math.NaN,
					() -> new SinglePrints(p, b), (i, bar) -> (cast i : SinglePrints).update(bar));
			}
		};
	}
}
