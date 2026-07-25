package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hurst exponent of the spread of two series — ported from wickra-core's
 * `SpreadHurst`
 * (vendor/wickra/crates/wickra-core/src/indicators/spread_hurst.rs).
 *
 * Each update takes one (a, b) price pair and forms the spread s_t = a_t − b_t.
 * Over the trailing window of `period` spreads it estimates the Hurst
 * exponent H from how the variance of τ-lagged differences grows with τ:
 *
 *   V(τ) = mean_t (s_{t+τ} − s_t)²  ∝  τ^(2H)
 *   H    = slope of log V(τ) on log τ, divided by two
 *
 * H < 0.5 mean-reverting, H ≈ 0.5 random walk, H > 0.5 trending. The fit uses
 * lags 1..period/4 (at least two). A flat spread (fewer than two usable
 * log-points) returns the neutral 0.5. Output is clamped to [0, 1].
 */
class SpreadHurst implements MuseIndicator<SpreadHurstPair, Float> {
	var period:Int;
	var maxLag:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 8) throw "SpreadHurst: period must be >= 8";
		this.period = period;
		var ml = Std.int(period / 4);
		maxLag = ml > 2 ? ml : 2;
		window = [];
	}

	public function update(input:SpreadHurstPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		if (window.length == period) window.shift();
		window.push(a - b);
		if (window.length < period) return null;
		// Collect (log τ, log V(τ)) for every lag whose variance is positive.
		var logLag:Array<Float> = [];
		var logVar:Array<Float> = [];
		for (lag in 1...maxLag + 1) {
			var sumSq = 0.0;
			var count = 0.0;
			for (i in 0...window.length - lag) {
				var diff = window[i + lag] - window[i];
				sumSq += diff * diff;
				count += 1.0;
			}
			var v = sumSq / count;
			if (v > 0.0) {
				logLag.push(Math.log(lag));
				logVar.push(Math.log(v));
			}
		}
		if (logLag.length < 2) {
			// Degenerate (flat) spread: report the random-walk midpoint.
			return 0.5;
		}
		var n:Float = logLag.length;
		var meanLag = 0.0;
		for (v in logLag) meanLag += v;
		meanLag /= n;
		var meanVar = 0.0;
		for (v in logVar) meanVar += v;
		meanVar /= n;
		var cov = 0.0;
		var varLag = 0.0;
		for (i in 0...logLag.length) {
			cov += (logLag[i] - meanLag) * (logVar[i] - meanVar);
			varLag += (logLag[i] - meanLag) * (logLag[i] - meanLag);
		}
		var slope = cov / varLag;
		var h = slope / 2.0;
		if (h < 0.0) h = 0.0;
		if (h > 1.0) h = 1.0;
		return h;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SpreadHurst";

	public static function spec():IndicatorSpec {
		return {
			name: "spread_hurst", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 60);
				var key = "spread_hurst:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new SpreadHurst(p),
					(i, a, b) -> (cast i : SpreadHurst).update({a: a, b: b}));
			}
		};
	}
}

@:structInit
class SpreadHurstPair {
	public var a:Float;
	public var b:Float;
}
