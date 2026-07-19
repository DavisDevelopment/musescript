package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Martin Ratio (Ulcer Performance Index): mean return divided by the Ulcer
 * Index (a root-mean-square drawdown measure), over a trailing window of
 * `period` equity samples.
 *
 * drawdown_i = (runningPeak_i - equity_i) / runningPeak_i * 100    (0 at a new high)
 * UlcerIndex = sqrt( mean(drawdown_i^2, period) )
 * Martin     = mean(return, period) / UlcerIndex
 *
 * Unlike Calmar (worst single drawdown) or Burke (sum of squared
 * drawdowns), the Ulcer Index averages squared drawdown over *every* bar in
 * the window, penalizing both depth and duration of time spent underwater.
 * Falls back to 0 when the Ulcer Index is exactly zero (no drawdown at all
 * in the window).
 */
class MartinRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "MartinRatio: period must be >= 2";
		this.period = period;
		window = [];
	}

	public function update(equity:Float):Null<Float> {
		if (!Math.isFinite(equity)) return null;
		if (window.length == period) window.shift();
		window.push(equity);
		if (window.length < period) return null;

		var peak = window[0];
		var sumSqDd = 0.0;
		var ddCount = 0;
		var sumReturn = 0.0;
		var returnCount = 0;
		for (i in 0...window.length) {
			var v = window[i];
			if (v > peak) peak = v;
			var dd = peak > 0.0 ? (peak - v) / peak * 100.0 : 0.0;
			sumSqDd += dd * dd;
			ddCount++;
			if (i > 0) {
				var prev = window[i - 1];
				if (prev != 0.0) { sumReturn += (v - prev) / prev; returnCount++; }
			}
		}
		var ulcer = Math.sqrt(sumSqDd / ddCount);
		if (ulcer == 0.0 || returnCount == 0) return 0.0;
		return (sumReturn / returnCount) / ulcer;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "MartinRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "martin_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "martin_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new MartinRatio(p), (i, v) -> (cast i : MartinRatio).update(v));
			}
		};
	}
}
