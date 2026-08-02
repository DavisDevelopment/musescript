package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Calmar Ratio: mean return over the trailing window divided by the single
 * worst peak-to-trough drawdown observed in that same window.
 *
 * Calmar = mean(return) / maxDrawdown
 *
 * where `maxDrawdown = max_i( (running_peak_i - equity_i) / running_peak_i )`.
 * Falls back to 0 when there has been no drawdown in the window (undefined
 * risk-adjustment with zero risk in the denominator).
 */
class CalmarRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period < 2) throw "CalmarRatio: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(equity:Float):Null<Float> {
		if (!Math.isFinite(equity)) return null;
		window.push(equity);
		if (window.length < period) return null;

		var peak = window.oldest(0);
		var maxDd = 0.0;
		var sumReturn = 0.0;
		var returnCount = 0;
		for (i in 1...window.length) {
			var prev = window.oldest(i - 1);
			var cur = window.oldest(i);
			if (prev != 0.0) {
				sumReturn += (cur - prev) / prev;
				returnCount++;
			}
			if (cur > peak) peak = cur;
			else if (peak > 0.0) {
				var dd = (peak - cur) / peak;
				if (dd > maxDd) maxDd = dd;
			}
		}

		if (returnCount == 0 || maxDd <= 0.0) return 0.0;
		return (sumReturn / returnCount) / maxDd;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CalmarRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "calmar_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 60);
				return IndicatorCache.evalSeries(h, "calmar_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new CalmarRatio(p), (i, v) -> (cast i : CalmarRatio).update(v));
			}
		};
	}
}
