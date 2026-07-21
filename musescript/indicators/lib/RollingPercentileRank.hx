package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Percentile Rank — ported from wickra-core's `RollingPercentileRank`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_percentile_rank.rs).
 *
 * Percentile rank of the most-recent value within the last `period` values,
 * in [0, 100]:
 *
 *   rank = 100 · (#below + 0.5 · #equal) / period
 *
 * This is the "mean" method of `percentileofscore`: ties are split
 * symmetrically, so a flat window scores exactly 50, the strict maximum just
 * under 100, and the strict minimum just over 0.
 */
class RollingPercentileRank implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "RollingPercentileRank: period must be > 0";
		this.period = period;
		window = [];
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) window.shift();
		window.push(value);
		if (window.length < period) return null;
		var below = 0;
		var equal = 0;
		for (x in window) {
			if (x < value) below++;
			else if (x == value) equal++;
		}
		return (below + 0.5 * equal) / period * 100.0;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "RollingPercentileRank";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_percentile_rank", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "rolling_percentile_rank:" + series + ":" + p, series, Math.NaN,
					() -> new RollingPercentileRank(p), (i, v) -> (cast i : RollingPercentileRank).update(v));
			}
		};
	}
}
