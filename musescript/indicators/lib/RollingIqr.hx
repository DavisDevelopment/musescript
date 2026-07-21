package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
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
	var window:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "RollingIqr: period must be > 0";
		this.period = period;
		window = [];
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) window.shift();
		window.push(value);
		if (window.length < period) return null;
		var scratch = window.copy();
		scratch.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var q1 = RollingQuantile.quantileSorted(scratch, 0.25);
		var q3 = RollingQuantile.quantileSorted(scratch, 0.75);
		return q3 - q1;
	}

	public function reset():Void {
		window = [];
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
