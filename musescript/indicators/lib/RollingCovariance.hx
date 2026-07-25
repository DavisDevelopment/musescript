package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling covariance of the period-over-period RETURNS of two synchronised
 * series — ported from wickra-core's `RollingCovariance`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_covariance.rs).
 *
 * Each update takes one (x, y) level pair, differences each channel into a
 * one-step return, and reports the population covariance of those returns:
 *
 *   rxₜ = xₜ − xₜ₋₁          ryₜ = yₜ − yₜ₋₁
 *   cov = (1/n) · Σ rx·ry − r̄x · r̄y
 *
 * Unlike `rolling_correlation` the result is NOT normalised to [−1, 1]: it
 * carries the units of the two return streams multiplied together. The first
 * level in each channel produces no return, so warmup is `period + 1`.
 */
class RollingCovariance implements MuseIndicator<RollingCovariancePair, Float> {
	var period:Int;
	var prev:Null<RollingCovariancePair>;
	var window:Array<RollingCovariancePair>;
	var sumX:Float;
	var sumY:Float;
	var sumXy:Float;

	public function new(period:Int) {
		if (period < 2) throw "RollingCovariance: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:RollingCovariancePair):Null<Float> {
		var x = input.x;
		var y = input.y;
		if (!Math.isFinite(x) || !Math.isFinite(y)) return null;
		if (prev == null) {
			prev = { x: x, y: y };
			return null;
		}
		var rx = x - prev.x;
		var ry = y - prev.y;
		prev = { x: x, y: y };
		if (window.length == period) {
			var old = window.shift();
			sumX -= old.x;
			sumY -= old.y;
			sumXy -= old.x * old.y;
		}
		window.push({ x: rx, y: ry });
		sumX += rx;
		sumY += ry;
		sumXy += rx * ry;
		if (window.length < period) return null;
		var n:Float = period;
		var meanX = sumX / n;
		var meanY = sumY / n;
		return sumXy / n - meanX * meanY;
	}

	public function reset():Void {
		prev = null;
		window = [];
		sumX = 0.0;
		sumY = 0.0;
		sumXy = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "RollingCovariance";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_covariance", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesX = IndicatorCache.seriesArg(args, 0, "close");
				var seriesY = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "rolling_covariance:" + seriesX + ":" + seriesY + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesX, seriesY, Math.NaN,
					() -> new RollingCovariance(p), (i, x, y) -> (cast i : RollingCovariance).update({ x: x, y: y }));
			}
		};
	}
}

@:structInit
class RollingCovariancePair {
	public var x:Float;
	public var y:Float;
}
