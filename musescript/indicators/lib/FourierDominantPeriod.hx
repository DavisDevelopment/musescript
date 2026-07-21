package musescript.indicators.lib;

import musescript.indicators.FourierMath;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Dominant cycle length via windowed DFT — a MuseScript-native builtin
 * (not a Wickra port; see FourierMath). The spectral sibling of the
 * Hilbert-transform `hilbert_dominant_cycle` port.
 *
 * Each bar, DFTs the last `period` values and returns the cycle length in
 * bars (`period / bin`) of the largest-amplitude non-DC bin. Ties break
 * toward the longer cycle, deterministically.
 *
 * Called `fourier_dominant_period(close, 64)`. Warmup: `period` bars.
 */
class FourierDominantPeriod implements MuseIndicator<Float, Float> {
	var period:Int;
	var buf:Array<Float>;
	var emitted:Bool;

	public function new(period:Int) {
		if (period < 4) throw "FourierDominantPeriod: period must be >= 4";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		buf.push(price);
		if (buf.length > period) buf.shift();
		if (buf.length < period) return null;

		var sp = FourierMath.spectrum(buf);
		var bins = FourierMath.topBins(sp.amp, 1);
		emitted = true;
		return bins.length > 0 ? period / bins[0] : Math.NaN;
	}

	public function reset():Void {
		buf = [];
		emitted = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return emitted;
	public function name():String return "FourierDominantPeriod";

	public static function spec():IndicatorSpec {
		return {
			name: "fourier_dominant_period", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 32);
				return IndicatorCache.evalSeries(h, 'fourier_dominant_period:$series:$p', series, Math.NaN,
					() -> new FourierDominantPeriod(p), (i, v) -> (cast i : FourierDominantPeriod).update(v));
			}
		};
	}
}
