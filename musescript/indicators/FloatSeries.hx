package musescript.indicators;

/**
 * Unboxed bar-by-bar float series backed by `haxe.ds.Vector<Float>` on JVM (`double[]`).
 * On JS: owned series use `Float64Array` (JIT guide §3.5); `fromVector` aliases keep the
 * shared `Vector` (plain Array) so prefix views stay zero-copy and mutations remain visible.
 *
 * Sibling of `GrowableVec<Float>` for feeds that need either incremental `push` OR a zero-copy
 * prefix view over an already-materialized tape.
 *
 * INDEXING: `at(i)` / `[i]` is absolute-from-start (0 = first element), matching plain
 * `Array<Float>` — same convention as `GrowableVec`, not `RingBuffer`'s recency indexing.
 *
 * TWO MODES:
 * - **Owned** (`new`, `fromArray`): the series owns its backing store; `push` grows the
 *   visible prefix and capacity-doubles via `Vector.blit` / `Float64Array.set` (native copy).
 * - **Aliased** (`fromVector`): wraps an existing `Vector<Float>` without copying; only the
 *   mutable `length` (visible prefix) changes as more bars become visible — the key shape for
 *   sliding prefix views over a full tape buffer.
 *
 * `fromArray` deliberately **copies once** into owned unboxed storage: on JVM,
 * `Array<Float>` is boxed (`java.lang.Double` per element), so the copy pays one boxed read
 * per slot and subsequent `at()`/`setAt()`/`push` stay unboxed. Prefer `fromVector` when the
 * tape is already a `Vector` and you only need a sliding visible prefix.
 *
 * Hot scans: indexed `for (i in 0...series.length) series.at(i)` — not `for..in` (JVM boxes
 * custom iterators; see `RingBuffer.hx` / `GrowableVec.hx` headers).
 */
class FloatSeries {
	#if js
	/** Owned path — null when this is a `fromVector` alias. */
	var f64:js.lib.Float64Array;
	/** Alias path — null when owned. */
	var vec:haxe.ds.Vector<Float>;
	#else
	var data:haxe.ds.Vector<Float>;
	#end
	var visibleLength:Int;
	var owned:Bool;

	public function new(?initialCapacity:Int = 8) {
		owned = true;
		var cap = initialCapacity != null && initialCapacity > 0 ? initialCapacity : 8;
		#if js
		f64 = new js.lib.Float64Array(cap);
		vec = null;
		#else
		data = new haxe.ds.Vector<Float>(cap);
		#end
		visibleLength = 0;
	}

	/** Visible element count — grows via `push` on owned series, or set directly as a prefix
	 * over a full backing tape (owned or aliased). Never exceeds `backingLength`. */
	public var length(get, set):Int;

	inline function get_length():Int return visibleLength;

	function set_length(n:Int):Int {
		if (n < 0)
			throw 'FloatSeries.length must be >= 0 (got $n)';
		if (n > backingLength) {
			if (!owned)
				throw 'FloatSeries.length $n exceeds backing store $backingLength';
			ensureCapacity(n);
		}
		visibleLength = n;
		return n;
	}

	/** Full backing store capacity (may exceed visible `length` on aliased prefix views). */
	public var backingLength(get, never):Int;

	inline function get_backingLength():Int {
		#if js
		return owned ? f64.length : vec.length;
		#else
		return data.length;
		#end
	}

	/** True when this series owns its backing store and may `push`; false for `fromVector` aliases. */
	public var isOwned(get, never):Bool;
	inline function get_isOwned():Bool return owned;

	public function push(v:Float):Void {
		if (!owned)
			throw "FloatSeries.push requires an owned series (fromVector aliases are prefix views only)";
		if (visibleLength >= backingLength)
			grow();
		#if js
		f64[visibleLength] = v;
		#else
		data[visibleLength] = v;
		#end
		visibleLength++;
	}

	public inline function at(i:Int):Float {
		#if js
		return owned ? f64[i] : vec[i];
		#else
		return data[i];
		#end
	}

	public inline function setAt(i:Int, v:Float):Void {
		#if js
		if (owned) f64[i] = v; else vec[i] = v;
		#else
		data[i] = v;
		#end
	}

	/**
	 * Copies `src` into owned unboxed storage. On JVM, each read from `src` may
	 * unbox a `java.lang.Double`; that cost is paid once here so later indexed access is fast.
	 * @param visible If set, copies and exposes only the first `visible` elements (default: all).
	 */
	public static function fromArray(src:Array<Float>, ?visible:Int):FloatSeries {
		var n = visible != null ? visible : src.length;
		if (n < 0 || n > src.length)
			throw 'FloatSeries.fromArray visible $n out of range for src.length ${src.length}';
		var s = new FloatSeries(n > 0 ? n : 8);
		#if js
		var arr = new js.lib.Float64Array(n > 0 ? n : 0);
		for (i in 0...n)
			arr[i] = src[i];
		s.f64 = arr;
		s.vec = null;
		#else
		var v = new haxe.ds.Vector<Float>(n > 0 ? n : 0);
		for (i in 0...n)
			v[i] = src[i];
		s.data = v;
		#end
		s.visibleLength = n;
		s.owned = true;
		return s;
	}

	/** Zero-copy prefix view over an existing tape buffer; `len` is the initially visible count. */
	public static function fromVector(src:haxe.ds.Vector<Float>, len:Int):FloatSeries {
		if (len < 0 || len > src.length)
			throw 'FloatSeries.fromVector len $len out of range for src.length ${src.length}';
		var s = new FloatSeries(0);
		#if js
		s.f64 = null;
		s.vec = src;
		#else
		s.data = src;
		#end
		s.visibleLength = len;
		s.owned = false;
		return s;
	}

	function grow():Void {
		var nextCap = backingLength > 0 ? backingLength * 2 : 8;
		#if js
		var next = new js.lib.Float64Array(nextCap);
		next.set(f64.subarray(0, visibleLength));
		f64 = next;
		#else
		var next = new haxe.ds.Vector<Float>(nextCap);
		haxe.ds.Vector.blit(data, 0, next, 0, visibleLength);
		data = next;
		#end
	}

	function ensureCapacity(min:Int):Void {
		if (min <= backingLength)
			return;
		var cap = backingLength > 0 ? backingLength : 8;
		while (cap < min)
			cap *= 2;
		#if js
		var next = new js.lib.Float64Array(cap);
		next.set(f64.subarray(0, visibleLength));
		f64 = next;
		#else
		var next = new haxe.ds.Vector<Float>(cap);
		haxe.ds.Vector.blit(data, 0, next, 0, visibleLength);
		data = next;
		#end
	}

	/**
	 * Zero-copy NdArray view when backing is contig f64. On JS, `fromVector`
	 * aliases use `Vector` (Array) — those copy once into owned NdArray storage.
	 */
	public function asNdArrayView():musescript.ndarray.NdArrayF64 {
		#if js
		if (owned) {
			return musescript.ndarray.NdArrayF64.aliasBuffer(f64, [visibleLength], 0);
		}
		// Aliased Vector path — copy into owned NdArray (JS Vector is Array)
		var out = musescript.ndarray.NdArrayF64.empty([visibleLength]);
		for (i in 0...visibleLength) out.setFlat(i, vec[i]);
		return out;
		#else
		return musescript.ndarray.NdArrayF64.aliasBuffer(data, [visibleLength], 0);
		#end
	}
}
