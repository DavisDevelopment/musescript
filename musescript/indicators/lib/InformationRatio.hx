package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Information Ratio: the mean excess return over a benchmark, divided by
 * the tracking-error (stddev of that excess), over a trailing window of
 * `period` `(asset_return, benchmark_return)` pairs.
 *
 * excess_t = asset_t - benchmark_t
 * IR = mean(excess, period) / stddev(excess, period)
 *
 * Falls back to 0 when tracking error is exactly zero (asset perfectly
 * mirrors the benchmark every bar in the window).
 */
class InformationRatio implements MuseIndicator<InformationRatioPair, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period < 2) throw "InformationRatio: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:InformationRatioPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		var excess = a - b;

		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(excess);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += excess;
		sumSq += excess * excess;
		if (window.length < period) return null;

		var mean = sum / period;
		var variance = Math.max(0.0, (sumSq / period) - mean * mean);
		var sd = Math.sqrt(variance);
		if (sd == 0.0) return 0.0;
		return mean / sd;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "InformationRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "information_ratio", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "information_ratio:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new InformationRatio(p), (i, a, b) -> (cast i : InformationRatio).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class InformationRatioPair {
	public var a:Float;
	public var b:Float;
}
