package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Pain Index — rolling mean drawdown depth.
 * Ported from wickra-core's `PainIndex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pain_index.rs).
 *
 * The Pain Index is the mean drawdown depth over the trailing window of `period` bars,
 * expressed as a non-negative fraction. Each update is O(period).
 *
 * peak_t   = running max over window up to t
 * dd_t     = (peak_t − equity_t) / peak_t          (0 if no drawdown)
 * PainIdx  = mean(dd_t over window)
 */
class PainIndex implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "PainIndex: period must be > 0";
		this.period = period;
		window = [];
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;

		if (window.length == period) {
			window.shift();
		}
		window.push(input);

		if (window.length < period) return null;

		var peak = Math.NEGATIVE_INFINITY;
		var sum_dd = 0.0;
		for (v in window) {
			if (v > peak) peak = v;
			if (peak > 0.0) {
				sum_dd += (peak - v) / peak;
			}
		}
		return sum_dd / period;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "PainIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "pain_index", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "pain_index:" + series + ":" + p, series, Math.NaN,
					() -> new PainIndex(p), (i, v) -> (cast i : PainIndex).update(v));
			}
		};
	}
}
