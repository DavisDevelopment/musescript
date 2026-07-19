package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Double Bollinger output: two nested band pairs sharing one middle line. */
typedef DoubleBollingerOutput = {
	var upper2:Float;
	var upper1:Float;
	var middle:Float;
	var lower1:Float;
	var lower2:Float;
}

/**
 * Double Bollinger Bands: the same SMA centerline as `Bollinger`, but with
 * two nested envelopes at different standard-deviation multipliers (an
 * "inner" zone and a wider "outer" zone), computed from one shared rolling
 * mean/variance pass.
 *
 * middle = SMA(period)
 * upperN/lowerN = middle +/- multiplierN * stddev(period)
 */
class DoubleBollinger implements MuseIndicator<Float, DoubleBollingerOutput> {
	var period:Int;
	var mult1:Float;
	var mult2:Float;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int, mult1:Float, mult2:Float) {
		if (period < 2) throw "DoubleBollinger: period must be >= 2";
		if (!Math.isFinite(mult1) || mult1 <= 0.0) throw "DoubleBollinger: mult1 must be positive and finite";
		if (!Math.isFinite(mult2) || mult2 <= 0.0) throw "DoubleBollinger: mult2 must be positive and finite";
		this.period = period;
		this.mult1 = mult1;
		this.mult2 = mult2;
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function update(input:Float):Null<DoubleBollingerOutput> {
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
		var variance = Math.max(0.0, (sumSq / period) - mean * mean);
		var sd = Math.sqrt(variance);
		return {
			upper2: mean + mult2 * sd,
			upper1: mean + mult1 * sd,
			middle: mean,
			lower1: mean - mult1 * sd,
			lower2: mean - mult2 * sd
		};
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "DoubleBollinger";

	public static function spec():IndicatorSpec {
		return {
			name: "double_bollinger", args: [TSeries, TWindow, TScalar, TScalar], ret: TObject([
				{name: "upper2", ty: TScalar}, {name: "upper1", ty: TScalar}, {name: "middle", ty: TScalar},
				{name: "lower1", ty: TScalar}, {name: "lower2", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var m1 = IndicatorCache.floatArg(args, 2, 1.0);
				var m2 = IndicatorCache.floatArg(args, 3, 2.0);
				var key = "double_bollinger:" + series + ":" + p + ":" + m1 + ":" + m2;
				var nanFill = { upper2: Math.NaN, upper1: Math.NaN, middle: Math.NaN, lower1: Math.NaN, lower2: Math.NaN };
				return IndicatorCache.evalSeries(h, key, series, nanFill,
					() -> new DoubleBollinger(p, m1, m2), (i, v) -> (cast i : DoubleBollinger).update(v));
			}
		};
	}
}
