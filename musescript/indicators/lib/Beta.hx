package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Beta: the asset's sensitivity to the benchmark over a trailing
 * window of `period` `(asset_return, benchmark_return)` pairs.
 *
 * Beta = cov(asset, bench) / var(bench)
 *
 * Falls back to 0 when the benchmark is flat (var(bench) == 0), since
 * sensitivity to a non-moving benchmark is undefined.
 */
class Beta implements MuseIndicator<BetaPair, Float> {
	var period:Int;
	var window:Array<BetaPair>;
	var sumA:Float;
	var sumB:Float;
	var sumBb:Float;
	var sumAb:Float;

	public function new(period:Int) {
		if (period < 2) throw "Beta: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:BetaPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;

		if (window.length == period) {
			var old = window.shift();
			sumA -= old.a;
			sumB -= old.b;
			sumBb -= old.b * old.b;
			sumAb -= old.a * old.b;
		}
		window.push({ a: a, b: b });
		sumA += a;
		sumB += b;
		sumBb += b * b;
		sumAb += a * b;

		if (window.length < period) return null;

		var n = period;
		var meanA = sumA / n;
		var meanB = sumB / n;
		var varB = (sumBb / n) - meanB * meanB;
		if (varB <= 0.0) return 0.0;
		var covAb = (sumAb / n) - meanA * meanB;
		return covAb / varB;
	}

	public function reset():Void {
		window = [];
		sumA = 0.0;
		sumB = 0.0;
		sumBb = 0.0;
		sumAb = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Beta";

	public static function spec():IndicatorSpec {
		return {
			name: "beta", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "beta:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new Beta(p), (i, a, b) -> (cast i : Beta).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class BetaPair {
	public var a:Float;
	public var b:Float;
}
