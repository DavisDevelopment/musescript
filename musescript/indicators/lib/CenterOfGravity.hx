package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Center of Gravity oscillator: a zero-lag, turning-point-focused
 * oscillator over a trailing window of `period` prices.
 *
 * COG = -( sum_{i=0}^{n-1} (i+1) * price[n-1-i] ) / sum(price)
 *
 * where price[n-1] is the most recent bar (weight 1) and price[0] is the
 * oldest bar in the window (weight n) — older bars get *heavier* weight,
 * which is what gives the oscillator its lead relative to price turns.
 */
class CenterOfGravity implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 2) throw "CenterOfGravity: period must be >= 2";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) window.shift();
		window.push(input);
		if (window.length < period) return null;

		var n = window.length;
		var weightedSum = 0.0;
		var sum = 0.0;
		for (i in 0...n) {
			// window[n-1] is newest (weight 1); window[0] is oldest (weight n).
			var weight = (n - i);
			weightedSum += weight * window[i];
			sum += window[i];
		}
		if (sum == 0.0) return 0.0;
		return -weightedSum / sum;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CenterOfGravity";

	public static function spec():IndicatorSpec {
		return {
			name: "center_of_gravity", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "center_of_gravity:" + series + ":" + p, series, Math.NaN,
					() -> new CenterOfGravity(p), (i, v) -> (cast i : CenterOfGravity).update(v));
			}
		};
	}
}
