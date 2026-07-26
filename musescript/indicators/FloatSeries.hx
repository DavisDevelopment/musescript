package musescript.indicators;

/**
 * Unboxed bar-by-bar float series backed by `haxe.ds.Vector<Float>` on JVM (`double[]`) and
 * `Float64Array` on JS (JIT guide §3.5 — V8 prefers typed arrays over `Vector`→plain `Array`).
 * Sibling of `GrowableVec<Float>` for feeds that need either incremental `push` OR a zero-copy
 * prefix view over an already-materialized tape.
 *
 * INDEXING: `at(i)` / `[i]` is absolute-from-start (0 = first element), matching plain
 * `Array<Float>` — same convention as `GrowableVec`, not `RingBuffer`'s recency indexing.
 *
 * TWO MODES:
 * - **Owned** (`new`, `fromArray`): the series owns its backing store; `push` grows the
 *   visible prefix and capacity-doubles via `Vector.blit` / `Float64Array.set` (native copy).
 * - **Aliased** (`fromVector`): wraps an existing `Vector<Float>` without copying on JVM; on
 *   JS copies once into a `Float64Array` (Vector is a plain Array there) so subsequent indexed
 *   reads stay on the typed-array elements kind. Only the mutable `length` (visible prefix)
 *   changes as more bars become visible — the key shape for `EngineIndicatorProvider`.
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
	var data:js.lib.Float64Array;
	#else
	var data:haxe.ds.Vector<Float>;
	#end
	var visibleLength:Int;
	var owned:Bool;

	public function new(?initialCapacity:Int = 8) {
		owned = true;
		var cap = initialCapacity != null && initialCapacity > 0 ? initialCapacity : 8;
		#if js
		data = new js.lib.Float64Array(cap);
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
		if (n > data.length) {
			if (!owned)
				throw 'FloatSeries.length $n exceeds backing store ${data.length}';
			ensureCapacity(n);
		}
		visibleLength = n;
		return n;
	}

	/** Full backing store capacity (may exceed visible `length` on aliased prefix views). */
	public var backingLength(get, never):Int;
	inline function get_backingLength():Int return data.length;

	/** True when this series owns `data` and may `push`; false for `fromVector` aliases. */
	public var isOwned(get, never):Bool;
	inline function get_isOwned():Bool return owned;

	public function push(v:Float):Void {
		if (!owned)
			throw "FloatSeries.push requires an owned series (fromVector aliases are prefix views only)";
		if (visibleLength >= data.length)
			grow();
		data[visibleLength] = v;
		visibleLength++;
	}

	public inline function at(i:Int):Float return data[i];

	public inline function setAt(i:Int, v:Float):Void data[i] = v;

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
		var vec = new js.lib.Float64Array(n > 0 ? n : 0);
		for (i in 0...n)
			vec[i] = src[i];
		#else
		var vec = new haxe.ds.Vector<Float>(n > 0 ? n : 0);
		for (i in 0...n)
			vec[i] = src[i];
		#end
		s.data = vec;
		s.visibleLength = n;
		s.owned = true;
		return s;
	}

	/** Prefix view over an existing tape buffer; `len` is the initially visible count.
	 * JVM: zero-copy alias of `Vector`. JS: one copy into `Float64Array` (Vector is a plain Array). */
	public static function fromVector(src:haxe.ds.Vector<Float>, len:Int):FloatSeries {
		if (len < 0 || len > src.length)
			throw 'FloatSeries.fromVector len $len out of range for src.length ${src.length}';
		var s = new FloatSeries(0);
		#if js
		var arr = new js.lib.Float64Array(src.length);
		var i = 0;
		while (i < src.length) {
			arr[i] = src[i];
			i++;
		}
		s.data = arr;
		s.visibleLength = len;
		s.owned = false;
		#else
		s.data = src;
		s.visibleLength = len;
		s.owned = false;
		#end
		return s;
	}

	function grow():Void {
		var nextCap = data.length > 0 ? data.length * 2 : 8;
		#if js
		var next = new js.lib.Float64Array(nextCap);
		next.set(data.subarray(0, visibleLength));
		data = next;
		#else
		var next = new haxe.ds.Vector<Float>(nextCap);
		haxe.ds.Vector.blit(data, 0, next, 0, visibleLength);
		data = next;
		#end
	}

	function ensureCapacity(min:Int):Void {
		if (min <= data.length)
			return;
		var cap = data.length > 0 ? data.length : 8;
		while (cap < min)
			cap *= 2;
		#if js
		var next = new js.lib.Float64Array(cap);
		next.set(data.subarray(0, visibleLength));
		data = next;
		#else
		var next = new haxe.ds.Vector<Float>(cap);
		haxe.ds.Vector.blit(data, 0, next, 0, visibleLength);
		data = next;
		#end
	}
}
