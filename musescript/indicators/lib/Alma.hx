package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Arnaud Legoux Moving Average (ALMA) — ported from wickra-core's `Alma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/alma.rs).
 *
 * A Gaussian-weighted moving average. Each output is a weighted sum of the last
 * `period` inputs, where the Gaussian is centred on the relative index
 * `offset * (period - 1)`. The default community-standard parameters are
 * `period = 9`, `offset = 0.85`, `sigma = 6.0`.
 *
 * Series input (f64): called `alma(close, period, offset, sigma)`.
 */
class Alma implements MuseIndicator<Float, Float> {
	var period:Int;
	var offset:Float;
	var sigma:Float;
	var weights:Array<Float>;
	var window:RingBuffer<Float>;
	var current:Null<Float>;

	public function new(period:Int, offset:Float, sigma:Float) {
		if (period <= 0) throw "Alma: period must be > 0";
		if (!Math.isFinite(offset) || offset < 0.0 || offset > 1.0) {
			throw "Alma: offset must be a finite value in [0, 1]";
		}
		if (!Math.isFinite(sigma) || sigma <= 0.0) {
			throw "Alma: sigma must be a finite positive value";
		}

		this.period = period;
		this.offset = offset;
		this.sigma = sigma;

		// Pre-compute normalised Gaussian weights.
		var m = offset * (period - 1.0);
		var s = period / sigma;
		var denom = 2.0 * s * s;

		var raw:Array<Float> = [];
		for (i in 0...period) {
			var exp_arg = -Math.pow(i - m, 2) / denom;
			raw.push(Math.exp(exp_arg));
		}

		var sum = 0.0;
		for (w in raw) sum += w;
		for (i in 0...raw.length) {
			raw[i] /= sum;
		}
		this.weights = raw;
		reset();
	}

	/** Classic ALMA with parameters (period=9, offset=0.85, sigma=6.0). */
	public static function classic():Alma {
		return new Alma(9, 0.85, 6.0);
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return current;
		window.push(input);
		if (window.length < period) return null;

		var acc = 0.0;
		// weights[i] were authored against Array-oldest-first indexing.
		for (i in 0...weights.length) {
			acc += weights[i] * window.oldest(i);
		}
		current = acc;
		return acc;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "ALMA";

	public static function spec():IndicatorSpec {
		return {
			name: "alma", args: [TSeries, TWindow, TScalar, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 9);
				var off = IndicatorCache.floatArg(args, 2, 0.85);
				var sig = IndicatorCache.floatArg(args, 3, 6.0);
				return IndicatorCache.evalSeries(h, "alma:" + series + ":" + p + ":" + off + ":" + sig, series, Math.NaN,
					() -> new Alma(p, off, sig), (i, v) -> (cast i : Alma).update(v));
			}
		};
	}
}
