package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Bollinger Bands output: upper/middle/lower bands. */
typedef BollingerOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Bollinger Bands: an SMA centerline with bands `numStdDev` sample standard
 * deviations away, both computed over the same trailing window of `period`
 * values.
 *
 * middle = SMA(period)
 * upper  = middle + numStdDev * stddev(period)
 * lower  = middle - numStdDev * stddev(period)
 */
class Bollinger implements MuseIndicator<Float, BollingerOutput> {
	var period:Int;
	var numStdDev:Float;
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int, numStdDev:Float) {
		if (period < 2) throw "Bollinger: period must be >= 2";
		if (!Math.isFinite(numStdDev) || numStdDev <= 0.0) throw "Bollinger: numStdDev must be positive and finite";
		this.period = period;
		this.numStdDev = numStdDev;
		reset();
	}

	public function update(input:Float):Null<BollingerOutput> {
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
		return { upper: mean + numStdDev * sd, middle: mean, lower: mean - numStdDev * sd };
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Bollinger";

	public static function spec():IndicatorSpec {
		return {
			name: "bollinger", args: [TSeries, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var k = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "bollinger:" + series + ":" + p + ":" + k;
				return IndicatorCache.evalSeries(h, key, series, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new Bollinger(p, k), (i, v) -> (cast i : Bollinger).update(v));
			}
		};
	}
}
