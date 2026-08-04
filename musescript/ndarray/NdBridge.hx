package musescript.ndarray;

import musescript.indicators.GrowableVec;
import musescript.indicators.GrowableVec.GrowableFloatImpl;
import musescript.indicators.FloatSeries;
import musescript.harness.Bar;

/**
 * Zero-copy (when contig f64) bridges into `NdArrayF64`.
 *
 * GrowableVec / FloatSeries owned buffers share storage; growing a GrowableVec
 * reallocates and **invalidates** prior views — re-bridge after grow.
 * Bar.data columns are per-bar scalars → always copy into a new 1-D array.
 */
class NdBridge {
	/**
	 * View over a float `GrowableVec` prefix. Same buffer when the runtime
	 * resolves to `GrowableFloatImpl` (always for `GrowableVec<Float>`).
	 */
	public static function fromGrowable(g:GrowableVec<Float>):NdArrayF64 {
		if (g == null) return NdArrayF64.empty([0]);
		var impl:GrowableFloatImpl = cast g;
		return impl.asNdArrayView();
	}

	/** Copy path — safe if the caller may grow the vec while holding the array. */
	public static function fromGrowableCopy(g:GrowableVec<Float>):NdArrayF64 {
		if (g == null) return NdArrayF64.empty([0]);
		var n = g.length;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) out.setFlat(i, g.at(i));
		return out;
	}

	/**
	 * View / alias when `FloatSeries` owns a contig f64 buffer (JS TypedArray or
	 * JVM Vector). Aliased Vector-backed series on JS copies (backing is Array).
	 */
	public static function fromFloatSeries(s:FloatSeries):NdArrayF64 {
		if (s == null) return NdArrayF64.empty([0]);
		return s.asNdArrayView();
	}

	public static function fromFloatSeriesCopy(s:FloatSeries):NdArrayF64 {
		if (s == null) return NdArrayF64.empty([0]);
		var n = s.length;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) out.setFlat(i, s.at(i));
		return out;
	}

	/** Build 1-D column from `Bar.data[key]` across bars (copy). Missing → NaN. */
	public static function fromBarDataColumn(bars:Array<Bar>, key:String):NdArrayF64 {
		if (bars == null || key == null) return NdArrayF64.empty([0]);
		var n = bars.length;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) {
			var b = bars[i];
			if (b == null || b.data == null || !b.data.exists(key)) out.setFlat(i, Math.NaN);
			else out.setFlat(i, b.data.get(key));
		}
		return out;
	}

	/** Contiguous f64 feature-tape / packed slot → view (caller owns buffer lifetime). */
	#if js
	public static function fromFeatureTape(buf:js.lib.Float64Array, length:Int, ?offset:Int = 0):NdArrayF64 {
		if (buf == null || length < 0) return NdArrayF64.empty([0]);
		return NdArrayF64.aliasBuffer(buf, [length], offset);
	}
	#else
	public static function fromFeatureTape(buf:haxe.ds.Vector<Float>, length:Int, ?offset:Int = 0):NdArrayF64 {
		if (buf == null || length < 0) return NdArrayF64.empty([0]);
		return NdArrayF64.aliasBuffer(buf, [length], offset);
	}
	#end
}
