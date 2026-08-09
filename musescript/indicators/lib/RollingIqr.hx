package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.SortedWindow;
import musescript.types.MuseType;

/**
 * Rolling Interquartile Range — ported from wickra-core's `RollingIqr`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_iqr.rs).
 *
 * IQR of the last `period` values: `Q3 − Q1`, the width of the central 50%
 * of the window. A robust dispersion measure: a single spike barely moves it.
 * Both quartiles use the type-7 / NumPy-default linearly-interpolated
 * definition, identical to `RollingQuantile`.
 */
class RollingIqr implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:SortedWindow;

	public function new(period:Int) {
		if (period <= 0) throw "RollingIqr: period must be > 0";
		this.period = period;
		window = new SortedWindow(period);
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		window.push(value);
		if (window.length < period) return null;
		return window.quantile(0.75) - window.quantile(0.25);
	}

	public function reset():Void {
		window = new SortedWindow(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "RollingIqr";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_iqr", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "rolling_iqr:" + series + ":" + p, series, Math.NaN,
					() -> new RollingIqr(p), (i, v) -> (cast i : RollingIqr).update(v));
			}
		};
	}
}
