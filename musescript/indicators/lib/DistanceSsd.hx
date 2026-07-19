package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Distance Sum of Squared Differences: the rolling sum of squared
 * pointwise differences between two series over a trailing window of
 * `period` pairs — a simple, scale-sensitive divergence measure often used
 * to detect pairs drifting apart (or as a raw pairs-trading spread energy).
 *
 * SSD = sum_{i in window} (a_i - b_i)^2
 */
class DistanceSsd implements MuseIndicator<DistanceSsdPair, Float> {
	var period:Int;
	var window:Array<Float>;
	var sum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "DistanceSsd: period must be > 0";
		this.period = period;
		window = [];
		sum = 0.0;
	}

	public function update(input:DistanceSsdPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		var sq = (a - b) * (a - b);

		if (window.length == period) sum -= window.shift();
		window.push(sq);
		sum += sq;

		if (window.length < period) return null;
		return sum;
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "DistanceSsd";

	public static function spec():IndicatorSpec {
		return {
			name: "distance_ssd", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "distance_ssd:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new DistanceSsd(p), (i, a, b) -> (cast i : DistanceSsd).update({ a: a, b: b }));
			}
		};
	}
}

typedef DistanceSsdPair = { a: Float, b: Float };
