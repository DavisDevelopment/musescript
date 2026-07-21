package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Quantile — ported from wickra-core's `RollingQuantile`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_quantile.rs).
 *
 * The `quantile`-th quantile of the last `period` values, with linear
 * interpolation between order statistics (type-7 / NumPy-default):
 *
 *   h      = (period − 1) · quantile
 *   result = sorted[⌊h⌋] + (h − ⌊h⌋) · (sorted[⌊h⌋ + 1] − sorted[⌊h⌋])
 *
 * `quantile = 0.0` returns the window minimum, `0.5` the median, `1.0` the
 * maximum. Each update copies the window into a scratch buffer and sorts it.
 */
class RollingQuantile implements MuseIndicator<Float, Float> {
	var period:Int;
	var quantile:Float;
	var window:Array<Float>;

	public function new(period:Int, quantile:Float) {
		if (period <= 0) throw "RollingQuantile: period must be > 0";
		if (!Math.isFinite(quantile) || quantile < 0.0 || quantile > 1.0)
			throw "RollingQuantile: quantile must be a finite value in [0.0, 1.0]";
		this.period = period;
		this.quantile = quantile;
		window = [];
	}

	/** Linearly-interpolated quantile of a sorted, non-empty array (type-7). */
	public static function quantileSorted(sorted:Array<Float>, quantile:Float):Float {
		var n = sorted.length;
		if (n == 1) return sorted[0];
		var h = (n - 1) * quantile;
		var lower = Math.ffloor(h);
		var idx = Std.int(lower);
		// When quantile == 1.0, h == n − 1 and the interpolation neighbour
		// would be out of bounds — return the top.
		if (idx >= n - 1) return sorted[n - 1];
		var frac = h - lower;
		return sorted[idx] + frac * (sorted[idx + 1] - sorted[idx]);
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		if (window.length == period) window.shift();
		window.push(value);
		if (window.length < period) return null;
		var scratch = window.copy();
		scratch.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return quantileSorted(scratch, quantile);
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "RollingQuantile";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_quantile", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				var q = IndicatorCache.floatArg(args, 2, 0.5);
				return IndicatorCache.evalSeries(h, "rolling_quantile:" + series + ":" + p + ":" + q, series, Math.NaN,
					() -> new RollingQuantile(p, q), (i, v) -> (cast i : RollingQuantile).update(v));
			}
		};
	}
}
