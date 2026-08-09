package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Tail Ratio — ported from wickra-core's `TailRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/tail_ratio.rs).
 *
 * TailRatio = P95(returns) / |P5(returns)|  over a trailing window of
 * `period` returns. Above `1.0` the right tail (upside surprises) is fatter
 * than the left; below `1.0` crashes are larger than rallies. Percentiles are
 * linearly interpolated over the sorted window (NumPy default). A window
 * whose 5th percentile is exactly zero reports `0.0` rather than dividing
 * by zero.
 */
class TailRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:SortedWindow;

	public function new(period:Int) {
		if (period < 2) throw "TailRatio: tail ratio needs period >= 2";
		this.period = period;
		reset();
	}

	function compute():Float {
		var upper = window.percentile(95.0);
		var lower = Math.abs(window.percentile(5.0));
		return lower > 0.0 ? upper / lower : 0.0;
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
	public function name():String return "TailRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "tail_ratio", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "tail_ratio:" + series + ":" + p, series, Math.NaN,
					() -> new TailRatio(p), (i, v) -> (cast i : TailRatio).update(v));
			}
		};
	}
}
