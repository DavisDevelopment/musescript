package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kendall's Tau: a rank correlation between two series over a trailing
 * window of `period` pairs — more robust to outliers than Pearson
 * correlation (see `Beta`/`Alpha`) since it only looks at pairwise
 * concordance, not magnitude.
 *
 * For every pair (i, j) in the window: concordant if both series move the
 * same direction between i and j, discordant if opposite, tied otherwise.
 *
 * tau = (concordant - discordant) / (n * (n-1) / 2)
 *
 * O(period^2) per bar (all-pairs comparison) — fine for the small windows
 * this indicator is meant to run over.
 */
class KendallTau implements MuseIndicator<KendallTauPair, Float> {
	var period:Int;
	var windowA:Array<Float>;
	var windowB:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "KendallTau: period must be >= 2";
		this.period = period;
		windowA = [];
		windowB = [];
	}

	public function update(input:KendallTauPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;

		if (windowA.length == period) windowA.shift();
		windowA.push(a);
		if (windowB.length == period) windowB.shift();
		windowB.push(b);
		if (windowA.length < period) return null;

		var n = windowA.length;
		var concordant = 0;
		var discordant = 0;
		for (i in 0...n) {
			for (j in (i + 1)...n) {
				var da = windowA[j] - windowA[i];
				var db = windowB[j] - windowB[i];
				var sign = da * db;
				if (sign > 0.0) concordant++;
				else if (sign < 0.0) discordant++;
			}
		}
		var totalPairs = n * (n - 1) / 2;
		if (totalPairs == 0) return 0.0;
		return (concordant - discordant) / totalPairs;
	}

	public function reset():Void {
		windowA = [];
		windowB = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return windowA.length == period;
	public function name():String return "KendallTau";

	public static function spec():IndicatorSpec {
		return {
			name: "kendall_tau", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "kendall_tau:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new KendallTau(p), (i, a, b) -> (cast i : KendallTau).update({ a: a, b: b }));
			}
		};
	}
}

typedef KendallTauPair = { a: Float, b: Float };
