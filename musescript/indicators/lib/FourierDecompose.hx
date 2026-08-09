package musescript.indicators.lib;

import musescript.indicators.FourierMath;
import musescript.indicators.RingBuffer;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Fourier decomposition of the trailing price window — a MuseScript-native
 * builtin (not a Wickra port; see FourierMath for the shared DFT).
 *
 * Each bar, DFTs the last `period` values and returns the top-`k`
 * cyclic components by amplitude as a flat Vector:
 *
 *   [mean, period_1, amp_1, phase_1, period_2, amp_2, phase_2, ...]
 *
 * `period_i` is the component's cycle length in bars (window/bin),
 * `phase_i` is radians relative to the window START (the bar
 * `period - 1` bars ago), matching FourierMath's cosine synthesis —
 * so the current bar sits at sample index `period - 1`. Components are
 * sorted by amplitude descending (ties → longer cycle first). Fewer than
 * `k` components exist when `k > period/2`; the vector is short then.
 *
 * Called `fourier_decompose(close, 64, 3)`. Warmup: `period` bars.
 */
class FourierDecompose implements MuseIndicator<Float, Array<Float>> {
	var period:Int;
	var k:Int;
	var buf:RingBuffer<Float>;
	var emitted:Bool;

	public function new(period:Int, k:Int) {
		if (period < 4) throw "FourierDecompose: period must be >= 4";
		if (k < 0) throw "FourierDecompose: k must be >= 0";
		this.period = period;
		this.k = k;
		reset();
	}

	public function update(price:Float):Null<Array<Float>> {
		if (!Math.isFinite(price)) return null;
		buf.push(price);
		if (buf.length < period) return null;
		var xs = [for (i in 0...buf.length) buf.oldest(i)];

		var sp = FourierMath.spectrum(xs);
		var bins = FourierMath.topBins(sp.amp, k);
		var out:Array<Float> = [sp.amp[0] * Math.cos(sp.phase[0])];
		for (m in bins) {
			out.push(period / m);
			out.push(sp.amp[m]);
			out.push(sp.phase[m]);
		}
		emitted = true;
		return out;
	}

	public function reset():Void {
		buf = new RingBuffer(period);
		emitted = false;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return emitted;
	public function name():String return "FourierDecompose";

	public static function spec():IndicatorSpec {
		return {
			name: "fourier_decompose", args: [TSeries, TWindow, TScalar], ret: TVector, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 32);
				var k = IndicatorCache.intArg(args, 2, 3);
				return IndicatorCache.evalSeries(h, 'fourier_decompose:$series:$p:$k', series, ([] : Array<Float>),
					() -> new FourierDecompose(p, k), (i, v) -> (cast i : FourierDecompose).update(v));
			}
		};
	}
}
