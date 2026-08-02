package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Burke Ratio: a drawdown-aware risk-adjusted return metric over a trailing
 * window of `period` equity-curve samples.
 *
 * Burke = mean(return) / sqrt( sum(drawdown_i^2) )
 *
 * where `return_i = (equity_i - equity_{i-1}) / equity_{i-1}` and
 * `drawdown_i = (running_peak - equity_i) / running_peak` is the fractional
 * distance below the running peak at each point in the window (0 while at a
 * new high). Unlike the Calmar ratio (which penalizes only the single worst
 * drawdown), Burke penalizes the *sum of squared* drawdowns across the whole
 * window — a large number of moderate drawdowns is punished, not just one
 * deep one. Falls back to 0 when there has been no drawdown in the window
 * (undefined risk-adjustment with zero risk in the denominator).
 */
class BurkeRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "BurkeRatio: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(equity:Float):Null<Float> {
		if (!Math.isFinite(equity)) return null;
		window.push(equity);
		if (window.length < period) return null;

		var returns:Array<Float> = [];
		var peak = window.oldest(0);
		var sumSqDd = 0.0;
		for (i in 1...window.length) {
			var prev = window.oldest(i - 1);
			var cur = window.oldest(i);
			if (prev != 0.0) returns.push((cur - prev) / prev);
			if (cur > peak) peak = cur;
			else if (peak > 0.0) {
				var dd = (peak - cur) / peak;
				sumSqDd += dd * dd;
			}
		}

		if (returns.length == 0 || sumSqDd <= 0.0) return 0.0;
		var meanReturn = 0.0;
		for (r in returns) meanReturn += r;
		meanReturn /= returns.length;
		return meanReturn / Math.sqrt(sumSqDd);
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "BurkeRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "burke_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 60);
				return IndicatorCache.evalSeries(h, "burke_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new BurkeRatio(p), (i, v) -> (cast i : BurkeRatio).update(v));
			}
		};
	}
}
