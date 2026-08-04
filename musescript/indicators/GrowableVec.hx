package musescript.indicators;

/**
 * Growable (unbounded) primitive-fast-path vector -- the sibling of `RingBuffer<T>` for series
 * that accumulate to full backtest length instead of a fixed rolling window (e.g.
 * `IndicatorColumns.IndCol.a`/`.b`, the incremental per-callsite indicator columns extended
 * once per bar forever). Same `@:multiType` mechanism, same Float-fast-path-via-plain-non-generic-
 * class design as `RingBuffer<T>` (see that file's doc comment for the full empirical
 * justification -- `@:generic` doesn't propagate through an abstract's constructor, `for..in`
 * always boxes on the jvm target regardless of iterator implementation, etc.) -- read that first
 * if this one is confusing.
 *
 * INDEXING CONVENTION DIFFERS FROM RingBuffer: `at(i)`/`[i]` here is absolute-from-start, exactly
 * matching plain `Array<T>` indexing (`vec[0]` = first pushed, `vec[length-1]` = most recently
 * pushed) -- NOT RingBuffer's "i slots back from newest" convention. This matches how
 * `IndicatorColumns.IndCol.a`/`.b` are actually used throughout `TradeBuiltins.hx`: as
 * incrementally-extended series read by absolute bar-relative index (`col.a[i - 1]`, range scans
 * like `for (i in (m - len)...m) sum += col.a[i]`), never by recency.
 *
 * Indexed writes via `setAt` + `commitLength` are for known-length column fills (NMA kernels)
 * that would otherwise pay a bounds check on every `push`. `push` remains the incremental API.
 */
@:multiType(@:followWithAbstracts T)
abstract GrowableVec<T>(IGrowableVec<T>) {
	public function new(?initialCapacity:Int = 8);

	/** Appends `v`, growing the backing store (capacity-doubling) if needed. */
	public inline function push(v:T):Void this.push(v);

	/** Absolute index from the start (0 = first pushed), matching plain `Array<T>` indexing. */
	@:arrayAccess
	public inline function at(i:Int):T return this.at(i);

	/** Write at absolute index without changing `length` — pair with `commitLength` after a fill. */
	public inline function setAt(i:Int, v:T):Void this.setAt(i, v);

	/** Publish visible length after a bulk `setAt` fill (must be ≤ capacity). */
	public inline function commitLength(n:Int):Void this.commitLength(n);

	public var length(get, never):Int;
	inline function get_length():Int return this.getLength();

	/**
	 * Drop contents; keep the backing store. Hot sims (`OrderSim.reset`) call this instead of
	 * allocating a fresh vector so a recycled `OrderSim` does not re-grow from capacity 8 every run.
	 */
	public inline function clear():Void this.clear();

	/** Ensure the backing store can hold at least `n` elements without growing on the next pushes. */
	public inline function ensureCapacity(n:Int):Void this.ensureCapacity(n);

	/** Materializes a real, plain `Array<T>` -- pay this ONCE at an interop/output boundary
	 * (JSON serialization, a public result typedef locked to `Array<Float>`, a general-purpose
	 * builtin that also accepts plain author-written arrays) rather than changing that
	 * boundary's own type. A single O(n) copy at the end of a run is negligible next to the
	 * unboxed-write win across every push during the run. */
	public inline function toArray():Array<T> {
		var out = [];
		for (i in 0...this.getLength()) out.push(this.at(i));
		return out;
	}

	@:to static inline function toFloatImpl(t:IGrowableVec<Float>, ?initialCapacity:Int = 8):GrowableFloatImpl
		return new GrowableFloatImpl(initialCapacity);

	@:to static inline function toGenericImpl<T>(t:IGrowableVec<T>, ?initialCapacity:Int = 8):GrowableGenericImpl<T>
		return new GrowableGenericImpl<T>(initialCapacity);
}

interface IGrowableVec<T> {
	function push(v:T):Void;
	function at(i:Int):T;
	function setAt(i:Int, v:T):Void;
	function commitLength(n:Int):Void;
	function getLength():Int;
	function clear():Void;
	function ensureCapacity(n:Int):Void;
}

/** Float fast path: a plain (non-generic) class, so `Float` is concrete at ITS OWN definition
 * -- `data` is backed by a genuine primitive `double[]` on the JVM target, no monomorphization
 * required (see `RingBuffer.hx`'s doc comment for the full verification of this pattern).
 *
 * On JS, `haxe.ds.Vector<Float>` lowers to a plain `Array` (JIT guide §3.5). V8's elements kinds
 * specialize hard on typed arrays, so the JS emit uses `Float64Array` instead — same API,
 * contiguous doubles, no holey Number packing on every NMA column push/at. */
class GrowableFloatImpl implements IGrowableVec<Float> {
	#if js
	var data:js.lib.Float64Array;
	#else
	var data:haxe.ds.Vector<Float>;
	#end
	var length:Int = 0;

	public function new(?initialCapacity:Int = 8) {
		var cap = initialCapacity != null && initialCapacity > 0 ? initialCapacity : 8;
		#if js
		data = new js.lib.Float64Array(cap);
		#else
		data = new haxe.ds.Vector<Float>(cap);
		#end
	}

	public function push(v:Float):Void {
		if (length >= data.length) grow();
		data[length] = v;
		length++;
	}

	function grow():Void {
		#if js
		var next = new js.lib.Float64Array(data.length * 2);
		next.set(data);
		data = next;
		#else
		var next = new haxe.ds.Vector<Float>(data.length * 2);
		haxe.ds.Vector.blit(data, 0, next, 0, data.length);
		data = next;
		#end
	}

	public function at(i:Int):Float return data[i];

	public function setAt(i:Int, v:Float):Void data[i] = v;

	public function commitLength(n:Int):Void {
		length = n;
	}

	public function getLength():Int return length;

	public function clear():Void {
		length = 0;
	}

	public function ensureCapacity(n:Int):Void {
		if (n <= data.length) return;
		#if js
		var next = new js.lib.Float64Array(n);
		next.set(data.subarray(0, length));
		data = next;
		#else
		var next = new haxe.ds.Vector<Float>(n);
		haxe.ds.Vector.blit(data, 0, next, 0, length);
		data = next;
		#end
	}

	/**
	 * Zero-copy 1-D `NdArrayF64` view of the live prefix. Mutations alias.
	 * Capacity growth reallocates — call again after `push` that grow the store.
	 */
	public function asNdArrayView():musescript.ndarray.NdArrayF64 {
		return musescript.ndarray.NdArrayF64.aliasBuffer(data, [length], 0);
	}
}

/** Generic fallback for every T that isn't Float (this codebase's `@:structInit` pair classes,
 * etc.) -- ordinary `Array<T>`-backed; boxed on the JVM target like any other generic
 * container, but correct for arbitrary element types, and already grows natively so no manual
 * capacity-doubling needed here. */
class GrowableGenericImpl<T> implements IGrowableVec<T> {
	var data:Array<T>;

	public function new(?initialCapacity:Int = 8) {
		data = [];
	}

	public function push(v:T):Void data.push(v);
	public function at(i:Int):T return data[i];

	public function setAt(i:Int, v:T):Void {
		while (data.length <= i) data.push(null);
		data[i] = v;
	}

	public function commitLength(n:Int):Void {
		#if (js || hl || java || cpp || cs || python || lua || neko || php || eval)
		data.resize(n);
		#else
		while (data.length > n) data.pop();
		while (data.length < n) data.push(null);
		#end
	}

	public function getLength():Int return data.length;

	public function clear():Void {
		#if (js || hl || java || cpp || cs || python || lua || neko || php || eval)
		data.resize(0);
		#else
		data = [];
		#end
	}

	public function ensureCapacity(n:Int):Void {
		// Array grows on push; nothing to reserve cheaply across targets.
	}
}
