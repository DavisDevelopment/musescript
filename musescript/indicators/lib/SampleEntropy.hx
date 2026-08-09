package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Sample Entropy (SampEn) — ported from wickra-core's `SampleEntropy`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/sample_entropy.rs).
 *
 * Richman & Moorman's measure of how regular (predictable) a series is: the
 * negative log conditional probability that two sub-sequences similar for
 * `m` points stay similar at the next point.
 *
 *   tol    = r_factor · stddev(window)
 *   B      = # template pairs of length m   within tol   (i < j)
 *   A      = # template pairs of length m+1 within tol   (i < j)
 *   SampEn = − ln(A / B)
 *
 * A perfectly flat window (stddev == 0) is maximally regular and returns 0.
 * If no length-m pairs match, 0 is returned; if length-m pairs match but
 * none extend, the estimator falls back to `ln(B)`. Non-finite inputs are
 * ignored and the last computed value is returned. O(period²) per update.
 */
class SampleEntropy implements MuseIndicator<Float, Float> {
	var period:Int;
	var embDim:Int;
	var rFactor:Float;
	var window:RingBuffer<Float>;
	var last:Null<Float>;

	public function new(period:Int, m:Int, rFactor:Float) {
		if (period <= 0 || m <= 0) throw "SampleEntropy: period and m must be > 0";
		if (period < m + 2) throw "SampleEntropy: period must be >= m + 2";
		if (!Math.isFinite(rFactor) || rFactor <= 0.0)
			throw "SampleEntropy: r_factor must be finite and positive";
		this.period = period;
		this.embDim = m;
		this.rFactor = rFactor;
		window = new RingBuffer(period);
		last = null;
	}

	static function populationStddev(window:RingBuffer<Float>):Float {
		var n = window.length;
		var mean = 0.0;
		for (i in 0...n) mean += window.oldest(i);
		mean /= n;
		var variance = 0.0;
		for (i in 0...n) {
			var v = window.oldest(i);
			variance += (v - mean) * (v - mean);
		}
		variance /= n;
		if (variance < 0.0) variance = 0.0;
		return Math.sqrt(variance);
	}

	static function templatesMatch(window:RingBuffer<Float>, i:Int, j:Int, len:Int, tol:Float):Bool {
		for (k in 0...len) {
			if (Math.abs(window.oldest(i + k) - window.oldest(j + k)) > tol) return false;
		}
		return true;
	}

	function compute():Float {
		var std = populationStddev(window);
		if (std == 0.0) return 0.0;
		var tol = rFactor * std;
		var m = embDim;
		// Restrict both template lengths to the same index range so A and B
		// share their candidate pairs: there are `period − m` length-(m+1)
		// templates.
		var count = period - m;
		var matchesM = 0;
		var matchesM1 = 0;
		for (i in 0...count) {
			for (j in (i + 1)...count) {
				if (templatesMatch(window, i, j, m, tol)) {
					matchesM++;
					if (templatesMatch(window, i, j, m + 1, tol)) matchesM1++;
				}
			}
		}
		if (matchesM == 0) return 0.0;
		if (matchesM1 == 0) {
			// No length-(m+1) matches: fall back to one unseen count.
			return Math.log(matchesM);
		}
		return -Math.log(matchesM1 / matchesM);
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		window.push(input);
		if (window.length < period) return null;
		var out = compute();
		last = out;
		return out;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "SampleEntropy";

	public static function spec():IndicatorSpec {
		return {
			name: "sample_entropy", args: [TSeries, TWindow, TWindow, TScalar], ret: TScalar, minArgs: 4,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 50);
				var m = IndicatorCache.intArg(args, 2, 2);
				var r = IndicatorCache.floatArg(args, 3, 0.2);
				var key = "sample_entropy:" + series + ":" + p + ":" + m + ":" + r;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new SampleEntropy(p, m, r), (i, v) -> (cast i : SampleEntropy).update(v));
			}
		};
	}
}
