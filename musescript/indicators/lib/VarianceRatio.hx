package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Lo–MacKinlay variance ratio of the spread `a − b` at horizon `q` — ported
 * from wickra-core's `VarianceRatio`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/variance_ratio.rs).
 *
 * Each update takes one (a, b) price pair and forms the spread s = a − b.
 * Over the trailing window of `period` spreads:
 *
 *   rₜ    = sₜ − sₜ₋₁                             (one-step changes)
 *   VR(q) = Var(Σ of q consecutive r) / (q · Var(r))
 *
 * Under a random walk VR(q) = 1. VR < 1 flags mean reversion (negatively
 * autocorrelated changes), VR > 1 momentum/trending. Overlapping q-step
 * windows are used; a flat spread (zero one-step variance) returns the
 * random-walk null value 1. Output is always >= 0.
 */
class VarianceRatio implements MuseIndicator<VarianceRatioPair, Float> {
	var period:Int;
	var q:Int;
	var window:Array<Float>;

	public function new(period:Int, q:Int) {
		if (q < 2) throw "VarianceRatio: q must be >= 2";
		if (period < q + 2) throw "VarianceRatio: period must be >= q + 2";
		this.period = period;
		this.q = q;
		window = [];
	}

	public function update(input:VarianceRatioPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		if (window.length == period) window.shift();
		window.push(a - b);
		if (window.length < period) return null;
		// One-step changes.
		var returns = [for (i in 1...window.length) window[i] - window[i - 1]];
		var m:Float = returns.length;
		var mean = 0.0;
		for (r in returns) mean += r;
		mean /= m;
		var varOne = 0.0;
		for (r in returns) varOne += (r - mean) * (r - mean);
		varOne /= m;
		if (varOne <= 0.0) {
			// Flat spread: the random-walk null value.
			return 1.0;
		}
		// Overlapping q-step changes; their mean is q·mean by construction.
		var qMean = q * mean;
		var varQ = 0.0;
		var count = returns.length - q + 1;
		for (i in 0...count) {
			var y = 0.0;
			for (k in 0...q) y += returns[i + k];
			varQ += (y - qMean) * (y - qMean);
		}
		varQ /= count;
		return varQ / (q * varOne);
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "VarianceRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "variance_ratio", args: [TSeries, TSeries, TWindow, TWindow], ret: TScalar, minArgs: 4,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 60);
				var horizon = IndicatorCache.intArg(args, 3, 2);
				var key = "variance_ratio:" + seriesA + ":" + seriesB + ":" + p + ":" + horizon;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new VarianceRatio(p, horizon), (i, a, b) -> (cast i : VarianceRatio).update({ a: a, b: b }));
			}
		};
	}
}

typedef VarianceRatioPair = { a: Float, b: Float };
