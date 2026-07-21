package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Shannon Entropy — ported from wickra-core's `ShannonEntropy`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/shannon_entropy.rs).
 *
 * The Shannon information entropy (in bits) of the distribution of values in
 * a rolling window, after binning them into `bins` equal-width buckets over
 * [min, max] of the window:
 *
 *   p_i = count_i / period
 *   H   = − Σ p_i · log2(p_i)   (over non-empty bins)
 *
 * The output lies in [0, log2(bins)]. A degenerate window where every value
 * is identical (max == min) returns 0. Non-finite inputs are ignored and the
 * last computed value is returned instead.
 */
class ShannonEntropy implements MuseIndicator<Float, Float> {
	static var LN2 = Math.log(2.0);

	var period:Int;
	var bins:Int;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int, bins:Int) {
		if (period <= 0 || bins <= 0) throw "ShannonEntropy: period and bins must be > 0";
		if (bins < 2) throw "ShannonEntropy: bins must be >= 2";
		this.period = period;
		this.bins = bins;
		window = [];
		last = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;

		var min = Math.POSITIVE_INFINITY;
		var max = Math.NEGATIVE_INFINITY;
		for (v in window) {
			if (v < min) min = v;
			if (v > max) max = v;
		}
		if (max <= min) {
			// Degenerate window: all values identical -> zero entropy.
			last = 0.0;
			return 0.0;
		}
		var width = (max - min) / bins;
		var counts = [for (_ in 0...bins) 0];
		for (v in window) {
			// `(v - min) / width` is in [0, bins]; truncate toward zero and
			// clamp to the last bin so the index is always valid.
			var raw = Std.int((v - min) / width);
			var idx = raw < bins - 1 ? raw : bins - 1;
			counts[idx]++;
		}
		var n:Float = period;
		var h = 0.0;
		for (count in counts) {
			if (count > 0) {
				var p = count / n;
				h -= p * (Math.log(p) / LN2);
			}
		}
		last = h;
		return h;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "ShannonEntropy";

	public static function spec():IndicatorSpec {
		return {
			name: "shannon_entropy", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 32);
				var b = IndicatorCache.intArg(args, 2, 8);
				return IndicatorCache.evalSeries(h, "shannon_entropy:" + series + ":" + p + ":" + b, series, Math.NaN,
					() -> new ShannonEntropy(p, b), (i, v) -> (cast i : ShannonEntropy).update(v));
			}
		};
	}
}
