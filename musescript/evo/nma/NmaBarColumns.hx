package musescript.evo.nma;

import musescript.harness.Bar;
import musescript.indicators.FloatSeries;

/**
 * The OHLC + bar-index scalars of one tape, hoisted out of `Bar` into unboxed storage.
 *
 * `Bar` is a structural typedef, so on the JVM target it is an anonymous class and every
 * `bar.close` is `haxe.jvm.Jvm.readField(Object, String)` -- a string-keyed dynamic lookup
 * returning a **boxed** `java.lang.Double`. That is invisible until you put it on the per-bar
 * loop of every evaluation: `NmaFitness.runPrepared` reads `close` three or four times a bar
 * plus `open`/`high`/`low`/`index`, and at B bars x P genomes x every attribution column swap
 * it was the single largest allocator in the engine (JFR `jdk.ObjectAllocationSample`:
 * ~87 MB of `Double` in `runPrepared` and ~22 MB in `NmaPositionEval.featureAt` over a
 * pop=1000/gens=20 run).
 *
 * The fix is cadence (guide §31), not a `Bar` redesign: those five columns are a pure function
 * of the tape, so they are derived ONCE per tape into `haxe.ds.Vector` (a real `double[]` /
 * `int[]` on the JVM, unlike `Array<Float>` which boxes -- guide §3.1) and the hot loop indexes
 * them. `bars` is retained so a holder can check by reference that a cached instance still
 * describes the tape it is about to be used on.
 *
 * «κρατὴρ εἷς κεράννυται· πάντες ἐξ αὐτοῦ πίνουσιν.»
 */
class NmaBarColumns {
	/** The tape these columns were derived from -- identity guard for cached instances. */
	public final bars:Array<Bar>;

	public final n:Int;
	public final open:FloatSeries;
	public final high:FloatSeries;
	public final low:FloatSeries;
	public final close:FloatSeries;

	/** `bar.index` per bar. NOT assumed equal to the loop counter: `OrderSim` stamps fills with
	 * it, and an attribution prefix or a resampled feed can carry its own numbering. */
	public final index:haxe.ds.Vector<Int>;

	/** Wraps vectors the caller already filled -- lets `NmaFitness.tapeStateFor` derive these in
	 * the same single pass over `bars` that builds its boxed field arrays, paying one dynamic
	 * read per field per bar instead of two.
	 *
	 * On JS, copies into owned `Float64Array` series (guide §3.5) rather than aliasing the
	 * `Vector`→plain-Array — the sim loop then reads typed-array OHLC. JVM keeps the zero-copy
	 * `fromVector` alias over real `double[]`. */
	public function new(bars:Array<Bar>, n:Int, open:haxe.ds.Vector<Float>, high:haxe.ds.Vector<Float>,
			low:haxe.ds.Vector<Float>, close:haxe.ds.Vector<Float>, index:haxe.ds.Vector<Int>) {
		this.bars = bars;
		this.n = n;
		#if js
		this.open = ownedSeries(open, n);
		this.high = ownedSeries(high, n);
		this.low = ownedSeries(low, n);
		this.close = ownedSeries(close, n);
		#else
		this.open = FloatSeries.fromVector(open, n);
		this.high = FloatSeries.fromVector(high, n);
		this.low = FloatSeries.fromVector(low, n);
		this.close = FloatSeries.fromVector(close, n);
		#end
		this.index = index;
	}

	#if js
	static function ownedSeries(src:haxe.ds.Vector<Float>, n:Int):FloatSeries {
		var s = new FloatSeries(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			s.setAt(i, src[i]);
			i++;
		}
		s.length = n;
		return s;
	}
	#end

	/** Standalone derivation for callers with no per-tape record to hang these off.
	 *
	 * «ἅπαξ τρυγᾶται ἡ ἄμπελος· τὸν ἐνιαυτὸν ὁ οἶνος μένει.»
	 */
	public static function of(bars:Array<Bar>):NmaBarColumns {
		var n = bars.length;
		var open = new haxe.ds.Vector<Float>(n);
		var high = new haxe.ds.Vector<Float>(n);
		var low = new haxe.ds.Vector<Float>(n);
		var close = new haxe.ds.Vector<Float>(n);
		var index = new haxe.ds.Vector<Int>(n);
		var i = 0;
		while (i < n) {
			var b = bars[i];
			open[i] = b.open;
			high[i] = b.high;
			low[i] = b.low;
			close[i] = b.close;
			index[i] = b.index;
			i++;
		}
		return new NmaBarColumns(bars, n, open, high, low, close, index);
	}
}
