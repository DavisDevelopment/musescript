package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Pearson correlation of the period-over-period RETURNS of two
 * synchronised series — ported from wickra-core's `RollingCorrelation`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rolling_correlation.rs).
 *
 * Where `pearson_correlation` correlates the raw levels (x, y), this
 * indicator first differences each channel into a one-step return and
 * correlates those returns over the trailing window:
 *
 *   rxₜ = xₜ − xₜ₋₁          ryₜ = yₜ − yₜ₋₁
 *   corr = cov(rx, ry) / √(var(rx) · var(ry))
 *
 * Output in [−1, +1] (clamped); a flat return channel makes the ratio
 * undefined and 0 is reported. The first level in each channel produces no
 * return, so a `period`-pair correlation needs `period + 1` updates of warmup.
 */
class RollingCorrelation implements MuseIndicator<RollingCorrelationPair, Float> {
	var period:Int;
	var prev:Null<RollingCorrelationPair>;
	var window:Array<RollingCorrelationPair>;
	var sumX:Float;
	var sumY:Float;
	var sumXx:Float;
	var sumYy:Float;
	var sumXy:Float;

	public function new(period:Int) {
		if (period < 2) throw "RollingCorrelation: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:RollingCorrelationPair):Null<Float> {
		var x = input.x;
		var y = input.y;
		if (!Math.isFinite(x) || !Math.isFinite(y)) return null;
		if (prev == null) {
			// First level in each channel: store it, no return yet.
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
			sumXx -= old.x * old.x;
			sumYy -= old.y * old.y;
			sumXy -= old.x * old.y;
		}
		window.push({ x: rx, y: ry });
		sumX += rx;
		sumY += ry;
		sumXx += rx * rx;
		sumYy += ry * ry;
		sumXy += rx * ry;
		if (window.length < period) return null;
		var n:Float = period;
		var meanX = sumX / n;
		var meanY = sumY / n;
		var varX = sumXx / n - meanX * meanX;
		if (varX < 0.0) varX = 0.0;
		var varY = sumYy / n - meanY * meanY;
		if (varY < 0.0) varY = 0.0;
		var cov = sumXy / n - meanX * meanY;
		var denom = Math.sqrt(varX * varY);
		if (denom == 0.0) {
			// At least one return channel is flat: correlation is undefined.
			return 0.0;
		}
		var r = cov / denom;
		if (r > 1.0) r = 1.0;
		if (r < -1.0) r = -1.0;
		return r;
	}

	public function reset():Void {
		prev = null;
		window = [];
		sumX = 0.0;
		sumY = 0.0;
		sumXx = 0.0;
		sumYy = 0.0;
		sumXy = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "RollingCorrelation";

	public static function spec():IndicatorSpec {
		return {
			name: "rolling_correlation", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesX = IndicatorCache.seriesArg(args, 0, "close");
				var seriesY = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "rolling_correlation:" + seriesX + ":" + seriesY + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesX, seriesY, Math.NaN,
					() -> new RollingCorrelation(p), (i, x, y) -> (cast i : RollingCorrelation).update({ x: x, y: y }));
			}
		};
	}
}

typedef RollingCorrelationPair = { x: Float, y: Float };
