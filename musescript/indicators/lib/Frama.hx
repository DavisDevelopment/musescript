package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Fractal Adaptive Moving Average (Ehlers): an EMA-style average whose decay
 * factor is driven bar-by-bar by an estimate of price's fractal dimension —
 * choppy/self-similar price gets a slow, noise-rejecting average; smoothly
 * trending price gets a fast, tightly-tracking one.
 *
 * `period` must be even (split into two equal halves). Over the trailing
 * `period` bars:
 *
 * N1 = (highestHigh(first half) - lowestLow(first half)) / (period/2)
 * N2 = (highestHigh(second half) - lowestLow(second half)) / (period/2)
 * N3 = (highestHigh(period) - lowestLow(period)) / period
 * D  = (ln(N1 + N2) - ln(N3)) / ln(2)          (fractal dimension, ~1..2)
 * alpha = clamp(exp(-4.6 * (D - 1)), 0.01, 1)
 * FRAMA_t = alpha * price_t + (1 - alpha) * FRAMA_{t-1}
 */
class Frama implements MuseIndicator<Float, Float> {
	var period:Int;
	var half:Int;
	var window:RingBuffer<Float>;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period < 4 || period % 2 != 0) throw "Frama: period must be an even number >= 4";
		this.period = period;
		half = Std.int(period / 2);
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return current;
		window.push(price);

		if (current == null) {
			current = price;
			return window.length < period ? null : current;
		}
		if (window.length < period) return null;

		var n1 = rangeOver(window, 0, half) / half;
		var n2 = rangeOver(window, half, period) / half;
		var n3 = rangeOver(window, 0, period) / period;

		var alpha = 1.0;
		if (n1 + n2 > 0.0 && n3 > 0.0) {
			var d = (Math.log(n1 + n2) - Math.log(n3)) / Math.log(2.0);
			alpha = Math.exp(-4.6 * (d - 1.0));
			if (alpha < 0.01) alpha = 0.01;
			if (alpha > 1.0) alpha = 1.0;
		}

		current = alpha * price + (1.0 - alpha) * current;
		return current;
	}

	/** Range over `window.oldest(lo)..oldest(hi-1)` (Array-equivalent indexing). */
	static function rangeOver(window:RingBuffer<Float>, lo:Int, hi:Int):Float {
		var hiV = window.oldest(lo);
		var loV = hiV;
		for (i in (lo + 1)...hi) {
			var v = window.oldest(i);
			if (v > hiV) hiV = v;
			if (v < loV) loV = v;
		}
		return hiV - loV;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period && current != null;
	public function name():String return "Frama";

	public static function spec():IndicatorSpec {
		return {
			name: "frama", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 16);
				return IndicatorCache.evalSeries(h, "frama:" + series + ":" + p, series, Math.NaN,
					() -> new Frama(p), (i, v) -> (cast i : Frama).update(v));
			}
		};
	}
}
