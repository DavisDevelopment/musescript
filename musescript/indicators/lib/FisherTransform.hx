package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ehlers' Fisher Transform: maps a rolling min-max-normalized price into a
 * Gaussian-ish distribution, sharpening turning points relative to raw
 * price oscillators.
 *
 * value_t = 2 * ((price - lowestLow(period)) / (highestHigh(period) - lowestLow(period)) - 0.5)
 * x_t     = clamp(0.33 * value_t + 0.67 * x_{t-1}, -0.999, 0.999)     (smoothed, clamped for atanh)
 * fisher_t = 0.5 * ln((1 + x_t) / (1 - x_t))
 * output   = 0.5 * fisher_t + 0.5 * output_{t-1}                      (Ehlers' own extra smoothing pass)
 */
class FisherTransform implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var x:Float;
	var output:Float;
	var seeded:Bool;

	public function new(period:Int) {
		if (period < 2) throw "FisherTransform: period must be >= 2";
		this.period = period;
		window = [];
		x = 0.0;
		output = 0.0;
		seeded = false;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (window.length == period) window.shift();
		window.push(price);
		if (window.length < period) return null;

		var hh = window[0];
		var ll = window[0];
		for (v in window) {
			if (v > hh) hh = v;
			if (v < ll) ll = v;
		}
		var range = hh - ll;
		var value = range == 0.0 ? 0.0 : 2.0 * ((price - ll) / range - 0.5);

		x = 0.33 * value + 0.67 * x;
		if (x > 0.999) x = 0.999;
		if (x < -0.999) x = -0.999;

		var fisher = 0.5 * Math.log((1.0 + x) / (1.0 - x));
		output = seeded ? 0.5 * fisher + 0.5 * output : fisher;
		seeded = true;
		return output;
	}

	public function reset():Void {
		window = [];
		x = 0.0;
		output = 0.0;
		seeded = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return seeded;
	public function name():String return "FisherTransform";

	public static function spec():IndicatorSpec {
		return {
			name: "fisher_transform", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "fisher_transform:" + series + ":" + p, series, Math.NaN,
					() -> new FisherTransform(p), (i, v) -> (cast i : FisherTransform).update(v));
			}
		};
	}
}
