package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Common Sense Ratio (Schwager/Carver) — ported from wickra-core's `CommonSenseRatio`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/common_sense_ratio.rs).
 *
 * Fuses profit factor (sum of gains / sum of losses) with tail ratio (P95 / |P5|)
 * to produce a single metric. Above 1.0 the strategy is sound on both body and tail;
 * below 1.0 something is working against it.
 *
 * CSR = ProfitFactor × TailRatio
 *
 * Sorted order statistics are maintained incrementally via `SortedWindow`.
 * A window with no losses or no left tail reports 0.0 rather than dividing by zero.
 */
class CommonSenseRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:SortedWindow;

	public function new(period:Int) {
		if (period < 2) throw "CommonSenseRatio: period must be >= 2";
		this.period = period;
		window = new SortedWindow(period);
	}

	function compute():Float {
		var gains = 0.0;
		var losses = 0.0;
		for (ret in window) {
			gains += Math.max(0.0, ret);
			losses += Math.max(0.0, -ret);
		}
		if (losses <= 0.0) {
			return 0.0;
		}
		var lowerTail = Math.abs(window.percentile(5.0));
		if (lowerTail <= 0.0) {
			return 0.0;
		}
		var profitFactor = gains / losses;
		var tailRatio = window.percentile(95.0) / lowerTail;
		return profitFactor * tailRatio;
	}

	public function update(ret:Float):Null<Float> {
		if (!Math.isFinite(ret)) return null;
		window.push(ret);
		if (window.length < period) return null;
		return compute();
	}

	public function reset():Void {
		window = new SortedWindow(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CommonSenseRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "common_sense_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var period = IndicatorCache.intArg(args, 1, 20);
				var key = "csr:" + series + ":" + period;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new CommonSenseRatio(period), (i, v) -> (cast i : CommonSenseRatio).update(v));
			}
		};
	}
}
