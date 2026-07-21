package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling historical Value-at-Risk — ported from wickra-core's `ValueAtRisk`
 * (vendor/wickra/crates/wickra-core/src/indicators/value_at_risk.rs).
 *
 * Input is a period return. Over the trailing window of `period` returns the
 * indicator reports the empirical lower-tail quantile at the `confidence`
 * level (e.g. `0.95` = the 95%-confident worst-case loss), sign-flipped to a
 * non-negative loss magnitude:
 *
 * q     = (1 − confidence)
 * VaR_t = − percentile(returns, q·100)   if it is negative, else 0
 *
 * The percentile uses linear interpolation between the two closest order
 * statistics ("type 7" / NumPy default). If the q-quantile is non-negative
 * (no losses in the window) the indicator returns `0.0`.
 */
class ValueAtRisk implements MuseIndicator<Float, Float> {
	var period:Int;
	var confidence:Float;
	var window:Array<Float>;

	public function new(period:Int, confidence:Float) {
		if (period < 2) throw "ValueAtRisk: value-at-risk needs period >= 2";
		if (!Math.isFinite(confidence) || confidence <= 0.0 || confidence >= 1.0)
			throw "ValueAtRisk: confidence must lie strictly between 0 and 1";
		this.period = period;
		this.confidence = confidence;
		reset();
	}

	/** Linear-interpolated percentile (type 7 / NumPy default) on a sorted array. */
	static function percentileSorted(sorted:Array<Float>, q:Float):Float {
		var n = sorted.length;
		var pos = q * (n - 1);
		var lo = Std.int(Math.floor(pos));
		var hi = Std.int(Math.ceil(pos));
		if (lo == hi) return sorted[lo];
		var frac = pos - lo;
		return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;
		var sorted = window.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var q = 1.0 - confidence;
		var cut = percentileSorted(sorted, q);
		// Loss magnitude (sign-flipped); 0 if quantile is non-negative.
		return -cut > 0.0 ? -cut : 0.0;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "ValueAtRisk";

	public static function spec():IndicatorSpec {
		return {
			name: "value_at_risk", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 100);
				var conf = IndicatorCache.floatArg(args, 2, 0.95);
				var key = "value_at_risk:" + series + ":" + p + ":" + conf;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new ValueAtRisk(p, conf), (i, v) -> (cast i : ValueAtRisk).update(v));
			}
		};
	}
}
