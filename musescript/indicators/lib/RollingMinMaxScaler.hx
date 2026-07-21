package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Min-Max Scaler — ported from wickra-core's `RollingMinMaxScaler`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_min_max_scaler.rs).
 *
 * Maps the current value onto [0, 1] relative to the minimum and maximum of
 * the trailing window:
 *
 *   scaled = (x − min(window)) / (max(window) − min(window))
 *
 * `0` means lowest in the window, `1` highest. A flat window (max == min)
 * has no range to scale against and returns the neutral `0.5`. Non-finite
 * inputs are ignored and the last computed value is returned instead.
 */
class RollingMinMaxScaler implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period < 2) throw "RollingMinMaxScaler: period must be >= 2";
		this.period = period;
		window = [];
		last = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;
		var min = Math.POSITIVE_INFINITY;
		var max = Math.NEGATIVE_INFINITY;
		for (v in window) {
			if (v < min) min = v;
			if (v > max) max = v;
		}
		var range = max - min;
		var scaled = range > 0.0 ? (input - min) / range : 0.5;
		last = scaled;
		return scaled;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "RollingMinMaxScaler";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_min_max_scaler", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "rolling_min_max_scaler:" + series + ":" + p, series, Math.NaN,
					() -> new RollingMinMaxScaler(p), (i, v) -> (cast i : RollingMinMaxScaler).update(v));
			}
		};
	}
}
