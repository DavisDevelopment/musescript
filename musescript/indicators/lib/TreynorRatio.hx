package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rolling Treynor Ratio — ported from wickra-core's `TreynorRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/treynor_ratio.rs).
 *
 * Each `update` receives one `(asset_return, benchmark_return)` pair. Over
 * the trailing window of `period` pairs:
 *
 * cov_ab  = (1/n) · Σ a·b − ā·b̄
 * var_b   = (1/n) · Σ b² − b̄²
 * Beta    = cov_ab / var_b
 * Treynor = (mean(asset) − risk_free) / Beta
 *
 * Sharpe's market-risk cousin: excess return per unit of benchmark
 * sensitivity (Beta) rather than own volatility. A flat benchmark window
 * (zero variance) or a zero Beta returns `0.0` rather than NaN.
 * Each `update` is O(1) via running `Σa`, `Σb`, `Σb²`, `Σa·b` sums.
 */
class TreynorRatio implements MuseIndicator<TreynorPair, Float> {
	var period:Int;
	var riskFree:Float;
	var window:RingBuffer<TreynorPair>;
	var sumA:Float;
	var sumB:Float;
	var sumBb:Float;
	var sumAb:Float;

	public function new(period:Int, riskFree:Float) {
		if (period < 2) throw "TreynorRatio: treynor ratio needs period >= 2";
		this.period = period;
		this.riskFree = riskFree;
		reset();
	}

	public function update(input:TreynorPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		var wasFull = window.isFull();
		var old = window.push({ a: a, b: b });
		if (wasFull) {
			sumA -= old.a;
			sumB -= old.b;
			sumBb -= old.b * old.b;
			sumAb -= old.a * old.b;
		}
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
		var beta = covAb / varB;
		if (beta == 0.0) return 0.0;
		return (meanA - riskFree) / beta;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sumA = 0.0;
		sumB = 0.0;
		sumBb = 0.0;
		sumAb = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "TreynorRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "treynor_ratio", args: [TSeries, TSeries, TWindow, TScalar], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var rf = IndicatorCache.floatArg(args, 3, 0.0);
				var key = "treynor_ratio:" + seriesA + ":" + seriesB + ":" + p + ":" + rf;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new TreynorRatio(p, rf), (i, a, b) -> (cast i : TreynorRatio).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class TreynorPair {
	public var a:Float;
	public var b:Float;
}
