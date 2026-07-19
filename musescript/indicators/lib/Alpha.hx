package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Jensen's Alpha (CAPM) — ported from wickra-core's `Alpha`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/alpha.rs).
 *
 * Each `update` receives one `(asset_return, benchmark_return)` pair. Over
 * the trailing window of `period` pairs:
 *
 * Beta  = cov(asset, bench) / var(bench)
 * Alpha = mean(asset) − ( risk_free + Beta · (mean(bench) − risk_free) )
 *
 * Alpha is the risk-adjusted excess return — the slice of the asset's
 * performance that cannot be explained by simple exposure to the
 * benchmark. If the benchmark is flat (var(bench) = 0) the indicator falls back to
 * alpha = mean(asset) − risk_free.
 *
 * Pair input: (asset_return, benchmark_return).
 */
class Alpha implements MuseIndicator<Pair, Float> {
	var period:Int;
	var riskFree:Float;
	var window:Array<Pair>;
	var sumA:Float;
	var sumB:Float;
	var sumBb:Float;
	var sumAb:Float;

	public function new(period:Int, riskFree:Float) {
		if (period < 2) throw "Alpha: period must be >= 2";
		this.period = period;
		this.riskFree = riskFree;
		reset();
	}

	public function update(input:Pair):Null<Float> {
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

		if (varB <= 0.0) {
			// Undefined beta: report unadjusted excess.
			return meanA - riskFree;
		}
		var covAb = (sumAb / n) - meanA * meanB;
		var beta = covAb / varB;
		return meanA - (riskFree + beta * (meanB - riskFree));
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
	public function name():String return "Alpha";

	public static function spec():IndicatorSpec {
		return {
			name: "alpha", args: [TSeries, TSeries, TWindow, TScalar], ret: TScalar, minArgs: 4,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var rf = IndicatorCache.floatArg(args, 3, 0.0);
				var key = "alpha:" + seriesA + ":" + seriesB + ":" + p + ":" + rf;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new Alpha(p, rf), (i, a, b) -> (cast i : Alpha).update({ a: a, b: b }));
			}
		};
	}
}

typedef Pair = { a: Float, b: Float };
