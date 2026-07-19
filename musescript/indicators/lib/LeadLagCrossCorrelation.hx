package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Lead-Lag Cross-Correlation: the Pearson correlation between series A
 * "now" and series B delayed by `lag` bars, over a trailing window of
 * `period` pairs — tests whether B tends to lead A by a fixed number of
 * bars. Fully causal: B's delay buffer only ever reaches into the past.
 *
 * corr( A_t, B_{t-lag} )   over the trailing window
 */
class LeadLagCrossCorrelation implements MuseIndicator<LeadLagPair, Float> {
	var period:Int;
	var lag:Int;
	var delayBuf:Array<Float>;
	var windowA:Array<Float>;
	var windowB:Array<Float>;

	public function new(period:Int, lag:Int) {
		if (period < 2) throw "LeadLagCrossCorrelation: period must be >= 2";
		if (lag < 0) throw "LeadLagCrossCorrelation: lag must be >= 0";
		this.period = period;
		this.lag = lag;
		delayBuf = [];
		windowA = [];
		windowB = [];
	}

	public function update(input:LeadLagPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;

		delayBuf.push(b);
		if (delayBuf.length <= lag) return null; // not enough history to look `lag` bars back yet
		var delayedB = delayBuf.shift();

		if (windowA.length == period) windowA.shift();
		windowA.push(a);
		if (windowB.length == period) windowB.shift();
		windowB.push(delayedB);

		if (windowA.length < period) return null;
		return correlation();
	}

	function correlation():Float {
		var n = windowA.length;
		var meanA = 0.0, meanB = 0.0;
		for (v in windowA) meanA += v;
		for (v in windowB) meanB += v;
		meanA /= n; meanB /= n;

		var cov = 0.0, varA = 0.0, varB = 0.0;
		for (i in 0...n) {
			var da = windowA[i] - meanA;
			var db = windowB[i] - meanB;
			cov += da * db;
			varA += da * da;
			varB += db * db;
		}
		var denom = Math.sqrt(varA * varB);
		if (denom == 0.0) return 0.0;
		return cov / denom;
	}

	public function reset():Void {
		delayBuf = [];
		windowA = [];
		windowB = [];
	}

	public function warmupPeriod():Int return period + lag;
	public function isReady():Bool return windowA.length == period;
	public function name():String return "LeadLagCrossCorrelation";

	public static function spec():IndicatorSpec {
		return {
			name: "lead_lag_cross_correlation", args: [TSeries, TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var lag = IndicatorCache.intArg(args, 3, 1);
				var key = "lead_lag_cross_correlation:" + seriesA + ":" + seriesB + ":" + p + ":" + lag;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new LeadLagCrossCorrelation(p, lag), (i, a, b) -> (cast i : LeadLagCrossCorrelation).update({ a: a, b: b }));
			}
		};
	}
}

typedef LeadLagPair = { a: Float, b: Float };
