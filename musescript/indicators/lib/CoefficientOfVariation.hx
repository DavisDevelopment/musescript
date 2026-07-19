package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Coefficient of Variation: the trailing sample standard deviation
 * normalized by the trailing mean, over a window of `period` values.
 *
 * CV = stddev(period) / mean(period) * 100
 *
 * A scale-free measure of relative dispersion. Falls back to 0 when the
 * mean is exactly zero (undefined ratio).
 */
class CoefficientOfVariation implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int) {
		if (period < 2) throw "CoefficientOfVariation: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) {
			var old = window.shift();
			sum -= old;
			sumSq -= old * old;
		}
		window.push(input);
		sum += input;
		sumSq += input * input;
		if (window.length < period) return null;

		var mean = sum / period;
		if (mean == 0.0) return 0.0;
		var variance = Math.max(0.0, (sumSq / period) - mean * mean);
		return Math.sqrt(variance) / mean * 100.0;
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CoefficientOfVariation";

	public static function spec():IndicatorSpec {
		return {
			name: "coefficient_of_variation", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "coefficient_of_variation:" + series + ":" + p, series, Math.NaN,
					() -> new CoefficientOfVariation(p), (i, v) -> (cast i : CoefficientOfVariation).update(v));
			}
		};
	}
}
