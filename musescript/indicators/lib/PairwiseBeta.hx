package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Pairwise Beta — rolling OLS slope of one asset's log-returns on another's,
 * ported from wickra-core's `PairwiseBeta`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pairwise_beta.rs).
 *
 * Each `update` receives raw price levels `(a, b)`. The indicator computes
 * log-returns internally and runs an OLS regression of a's returns on b's
 * returns over a rolling window. The result is the slope (beta) in return space,
 * measuring how much asset a moves per unit return of asset b.
 *
 * A non-positive or non-finite price breaks the return chain; the next valid
 * price restarts it.
 */
class PairwiseBeta implements MuseIndicator<PairwisePair, Float> {
	var period:Int;
	var prev:Null<PairwisePair>;
	var window:Array<PairwisePair>;
	var sumA:Float;
	var sumB:Float;
	var sumBb:Float;
	var sumAb:Float;

	public function new(period:Int) {
		if (period < 2) throw "PairwiseBeta: period must be >= 2";
		this.period = period;
		reset();
	}

	function pushReturn(ra:Float, rb:Float):Null<Float> {
		if (window.length == period) {
			var old = window.shift();
			sumA -= old.a;
			sumB -= old.b;
			sumBb -= old.b * old.b;
			sumAb -= old.a * old.b;
		}
		window.push({ a: ra, b: rb });
		sumA += ra;
		sumB += rb;
		sumBb += rb * rb;
		sumAb += ra * rb;
		if (window.length < period) return null;
		var n = period;
		var meanA = sumA / n;
		var meanB = sumB / n;
		var varB = (sumBb / n - meanB * meanB);
		if (varB < 0.0) varB = 0.0;
		var cov = sumAb / n - meanA * meanB;
		if (varB == 0.0) return 0.0;
		return cov / varB;
	}

	public function update(input:PairwisePair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!(a > 0.0 && b > 0.0 && Math.isFinite(a) && Math.isFinite(b))) {
			// Bad tick: drop it and restart the return chain.
			prev = null;
			return null;
		}
		if (prev == null) {
			prev = { a: a, b: b };
			return null;
		}
		var pa = prev.a;
		var pb = prev.b;
		prev = { a: a, b: b };
		var ra = Math.log(a / pa);
		var rb = Math.log(b / pb);
		return pushReturn(ra, rb);
	}

	public function reset():Void {
		prev = null;
		window = [];
		sumA = 0.0;
		sumB = 0.0;
		sumBb = 0.0;
		sumAb = 0.0;
	}

	public function warmupPeriod():Int {
		// One prior price to seed, then `period` return pairs.
		return period + 1;
	}

	public function isReady():Bool return window.length == period;
	public function name():String return "PairwiseBeta";

	public static function spec():IndicatorSpec {
		return {
			name: "pairwise_beta", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "pairwise_beta:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new PairwiseBeta(p), (i, a, b) -> (cast i : PairwiseBeta).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class PairwisePair {
	public var a:Float;
	public var b:Float;
}
