package musescript.indicators.lib;

import musescript.indicators.FourierMath;
import musescript.indicators.RingBuffer;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Fourier-based price projection — a MuseScript-native builtin (not a
 * Wickra port; see FourierMath for the shared DFT).
 *
 * Each bar: optionally least-squares-detrends the last `period` values
 * (`detrend`, default true — DFT assumes periodicity, so a raw trending
 * window aliases the trend into low-frequency cycles), DFTs the residual,
 * keeps the top-`k` cyclic components by amplitude, and extrapolates
 * trend + cycles `horizon` bars past the current bar. `horizon = 0` is the
 * current-bar resynthesis; on a stationary tape whose cycle lengths divide
 * `period`, the projection is exact (a test gate).
 *
 * The standard caveat applies doubly in markets: this extrapolates the
 * cyclic structure of the trailing window, it does not know news exists.
 *
 * Called `fourier_projection(close, 64, 3, 5)` or
 * `fourier_projection(close, 64, 3, 5, false)` to project the raw window.
 * Warmup: `period` bars.
 */
class FourierProjection implements MuseIndicator<Float, Float> {
	var period:Int;
	var k:Int;
	var horizon:Int;
	var detrend:Bool;
	var buf:RingBuffer<Float>;
	var emitted:Bool;

	public function new(period:Int, k:Int, horizon:Int, detrend:Bool = true) {
		if (period < 4) throw "FourierProjection: period must be >= 4";
		if (k < 0) throw "FourierProjection: k must be >= 0";
		if (horizon < 0) throw "FourierProjection: horizon must be >= 0";
		this.period = period;
		this.k = k;
		this.horizon = horizon;
		this.detrend = detrend;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		buf.push(price);
		if (buf.length < period) return null;
		var xs = [for (i in 0...buf.length) buf.oldest(i)];

		var slope = 0.0, intercept = 0.0;
		var x = xs;
		if (detrend) {
			var fit = FourierMath.linearFit(xs);
			slope = fit.slope;
			intercept = fit.intercept;
			x = [for (j in 0...period) xs[j] - (intercept + slope * j)];
		}
		var sp = FourierMath.spectrum(x);
		var bins = FourierMath.topBins(sp.amp, k);
		var j = (period - 1) + horizon;
		emitted = true;
		return intercept + slope * j + FourierMath.synth(period, bins, sp.amp, sp.phase, j);
	}

	public function reset():Void {
		buf = new RingBuffer(period);
		emitted = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return emitted;
	public function name():String return "FourierProjection";

	public static function spec():IndicatorSpec {
		return {
			name: "fourier_projection", args: [TSeries, TWindow, TScalar, TScalar, TBool], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 32);
				var k = IndicatorCache.intArg(args, 2, 3);
				var hor = IndicatorCache.intArg(args, 3, 1);
				var det = FourierMath.boolArg(args, 4, true);
				return IndicatorCache.evalSeries(h, 'fourier_projection:$series:$p:$k:$hor:$det', series, Math.NaN,
					() -> new FourierProjection(p, k, hor, det), (i, v) -> (cast i : FourierProjection).update(v));
			}
		};
	}
}
