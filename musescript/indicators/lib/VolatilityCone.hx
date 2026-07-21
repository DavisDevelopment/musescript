package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Volatility Cone output: current realized vol inside its historical envelope. */
typedef VolatilityConeOutput = {
	var current:Float;
	var min:Float;
	var median:Float;
	var max:Float;
	var percentile:Float;
}

/**
 * Volatility Cone — ported from wickra-core's `VolatilityCone`
 * (vendor/wickra/crates/wickra-core/src/indicators/volatility_cone.rs).
 *
 *   r_t   = ln(close_t / close_{t−1})
 *   vol_t = stddev_sample(r over window)
 *   cone  = { min, median, max, percentile } of vol over the last `lookback`
 *
 * Positions current realized volatility within its own history (Burghardt &
 * Lane 1990). Only the close is used; vol is per-period (not annualised).
 * Non-positive closes are skipped (state untouched, last value returned).
 * First value after `window + lookback` inputs.
 */
class VolatilityCone implements MuseIndicator<Bar, VolatilityConeOutput> {
	var window:Int;
	var lookback:Int;
	var prevClose:Null<Float>;
	/** Rolling window of log returns for the inner realized-volatility series. */
	var returns:Array<Float>;
	var retSum:Float;
	var retSumSq:Float;
	/** Rolling window of realized-volatility readings (the cone envelope). */
	var vols:Array<Float>;
	var last:Null<VolatilityConeOutput>;

	public function new(window:Int, lookback:Int) {
		if (window <= 0 || lookback <= 0) throw "VolatilityCone: period must be > 0";
		if (window < 2 || lookback < 2) throw "VolatilityCone: volatility cone window and lookback must both be >= 2";
		this.window = window;
		this.lookback = lookback;
		reset();
	}

	static function sampleStddev(sum:Float, sumSq:Float, count:Int):Float {
		var n:Float = count;
		var mean = sum / n;
		var variance = Math.max((sumSq - n * mean * mean) / (n - 1.0), 0.0);
		return Math.sqrt(variance);
	}

	public function update(candle:Bar):Null<VolatilityConeOutput> {
		var price = candle.close;
		// A log return is undefined for a non-positive close; skip the tick.
		if (price <= 0.0) return last;
		if (prevClose == null) {
			prevClose = price;
			return null;
		}
		var prev:Float = prevClose;
		prevClose = price;
		var r = Math.log(price / prev);

		// Stage one: rolling sample volatility of log returns.
		if (returns.length == window) {
			var old = returns.shift();
			retSum -= old;
			retSumSq -= old * old;
		}
		returns.push(r);
		retSum += r;
		retSumSq += r * r;
		if (returns.length < window) return null;
		var current = sampleStddev(retSum, retSumSq, window);

		// Stage two: maintain the lookback envelope of volatility readings.
		if (vols.length == lookback) vols.shift();
		vols.push(current);
		if (vols.length < lookback) return null;

		var sorted = vols.copy();
		sorted.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		var min = sorted[0];
		var max = sorted[lookback - 1];
		var mid = Std.int(lookback / 2);
		var median = lookback % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
		var countLe = 0;
		for (v in vols) if (v <= current) countLe++;
		var percentile = countLe / lookback * 100.0;

		var out:VolatilityConeOutput = {
			current: current,
			min: min,
			median: median,
			max: max,
			percentile: percentile
		};
		last = out;
		return out;
	}

	public function reset():Void {
		prevClose = null;
		returns = [];
		retSum = 0.0;
		retSumSq = 0.0;
		vols = [];
		last = null;
	}

	public function warmupPeriod():Int return window + lookback;
	public function isReady():Bool return last != null;
	public function name():String return "VolatilityCone";

	public static function spec():IndicatorSpec {
		return {
			name: "volatility_cone", args: [TWindow, TWindow], ret: TObject([
				{name: "current", ty: TScalar}, {name: "min", ty: TScalar}, {name: "median", ty: TScalar},
				{name: "max", ty: TScalar}, {name: "percentile", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var w = args.length > 0 ? IndicatorCache.intArg(args, 0, 20) : 20;
				var lb = IndicatorCache.intArg(args, 1, 60);
				var nanFill = { current: Math.NaN, min: Math.NaN, median: Math.NaN, max: Math.NaN, percentile: Math.NaN };
				return IndicatorCache.evalBar(h, "volatility_cone:" + w + ":" + lb, nanFill,
					() -> new VolatilityCone(w, lb), (i, b) -> (cast i : VolatilityCone).update(b));
			}
		};
	}
}
