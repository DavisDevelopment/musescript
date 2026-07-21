package musescript.indicators.lib;

import musescript.indicators.FourierMath;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Fourier recomposition (low-pass resynthesis) of the trailing price window
 * — a MuseScript-native builtin (not a Wickra port; see FourierMath).
 *
 * Each bar, DFTs the last `period` values, keeps the mean plus the top-`k`
 * cyclic components by amplitude, and resynthesizes the CURRENT bar's value
 * from just those — a zero-parameter-tuning Fourier smoother. With
 * `k >= period/2` every bin is kept and the output equals the input exactly
 * (completeness — a test gate). With `k = 0` it degrades to the rolling mean.
 *
 * Called `fourier_recompose(close, 64, 3)`. Warmup: `period` bars.
 */
class FourierRecompose implements MuseIndicator<Float, Float> {
	var period:Int;
	var k:Int;
	var buf:Array<Float>;
	var emitted:Bool;

	public function new(period:Int, k:Int) {
		if (period < 4) throw "FourierRecompose: period must be >= 4";
		if (k < 0) throw "FourierRecompose: k must be >= 0";
		this.period = period;
		this.k = k;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		buf.push(price);
		if (buf.length > period) buf.shift();
		if (buf.length < period) return null;

		var sp = FourierMath.spectrum(buf);
		var bins = FourierMath.topBins(sp.amp, k);
		emitted = true;
		return FourierMath.synth(period, bins, sp.amp, sp.phase, period - 1);
	}

	public function reset():Void {
		buf = [];
		emitted = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return emitted;
	public function name():String return "FourierRecompose";

	public static function spec():IndicatorSpec {
		return {
			name: "fourier_recompose", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 32);
				var k = IndicatorCache.intArg(args, 2, 3);
				return IndicatorCache.evalSeries(h, 'fourier_recompose:$series:$p:$k', series, Math.NaN,
					() -> new FourierRecompose(p, k), (i, v) -> (cast i : FourierRecompose).update(v));
			}
		};
	}
}
