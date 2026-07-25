package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Pearson correlation between two synchronised series — ported from
 * wickra-core's `PearsonCorrelation`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pearson_correlation.rs).
 *
 * Each `update` receives one `(x, y)` pair. Over the trailing window of `period`
 * pairs, the indicator computes the standardised covariance (Pearson's r),
 * measuring linear relationship in [−1, +1].
 *
 * Running sums maintain five accumulators (Σx, Σy, Σx², Σy², Σxy) for O(1) updates.
 * A flat series in either channel returns 0 instead of NaN.
 */
class PearsonCorrelation implements MuseIndicator<PearsonPair, Float> {
	var period:Int;
	var window:Array<PearsonPair>;
	var sumX:Float;
	var sumY:Float;
	var sumXx:Float;
	var sumYy:Float;
	var sumXy:Float;

	public function new(period:Int) {
		if (period < 2) throw "PearsonCorrelation: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:PearsonPair):Null<Float> {
		var x = input.x;
		var y = input.y;
		if (!Math.isFinite(x) || !Math.isFinite(y)) return null;

		if (window.length == period) {
			var old = window.shift();
			sumX -= old.x;
			sumY -= old.y;
			sumXx -= old.x * old.x;
			sumYy -= old.y * old.y;
			sumXy -= old.x * old.y;
		}
		window.push({ x: x, y: y });
		sumX += x;
		sumY += y;
		sumXx += x * x;
		sumYy += y * y;
		sumXy += x * y;

		if (window.length < period) return null;

		var n = period;
		var meanX = sumX / n;
		var meanY = sumY / n;
		var varX = (sumXx / n - meanX * meanX);
		if (varX < 0.0) varX = 0.0;
		var varY = (sumYy / n - meanY * meanY);
		if (varY < 0.0) varY = 0.0;
		var cov = sumXy / n - meanX * meanY;
		var denom = Math.sqrt(varX * varY);
		if (denom == 0.0) return 0.0;
		var r = cov / denom;
		// Clamp to [−1, +1] to absorb floating-point overshoots
		if (r > 1.0) r = 1.0;
		if (r < -1.0) r = -1.0;
		return r;
	}

	public function reset():Void {
		window = [];
		sumX = 0.0;
		sumY = 0.0;
		sumXx = 0.0;
		sumYy = 0.0;
		sumXy = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "PearsonCorrelation";

	public static function spec():IndicatorSpec {
		return {
			name: "pearson_correlation", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesX = IndicatorCache.seriesArg(args, 0, "close");
				var seriesY = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "pearson_correlation:" + seriesX + ":" + seriesY + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesX, seriesY, Math.NaN,
					() -> new PearsonCorrelation(p), (i, x, y) -> (cast i : PearsonCorrelation).update({ x: x, y: y }));
			}
		};
	}
}

@:structInit
class PearsonPair {
	public var x:Float;
	public var y:Float;
}
