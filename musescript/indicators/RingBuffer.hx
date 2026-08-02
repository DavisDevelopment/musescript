package musescript.indicators;

/**
 * Fixed-capacity circular buffer for rolling-window indicators, replacing the
 * `Array<T>` + `.shift()` + `.push()` pattern used throughout `indicators/lib/*` (see that
 * sub-package's original TODO, previously in RollingMinMaxScaler.hx). `Array.shift()` is O(n)
 * -- a real remove-and-compact, not a lazy head pointer -- so every windowed indicator paid
 * O(period) per bar just to evict the oldest sample; this pays O(1) via a head index that
 * wraps around a backing store sized ONCE at construction and never resized after.
 *
 * A genuine Haxe `@:multiType` abstract (the same mechanism `Map<K,V>` itself uses to pick
 * `StringMap`/`IntMap`/`ObjectMap` per key type -- see `std/haxe/ds/Map.hx`) -- NOT a plain
 * generic class. This matters specifically for the JVM target: a plain `class RingBuffer<T>`
 * backed by `Array<T>`/`Vector<T>` boxes every element as `java.lang.Double` regardless of T,
 * because an ordinary Haxe generic type parameter erases to `Object` on the JVM (verified by
 * decompiling probe bytecode -- see the `musescript-graal-jit-optimization` memory). `@:generic`
 * CAN produce a real monomorphized class with a true primitive `double[]` field, but ONLY when
 * the concrete type is visible at a non-generic instantiation site (e.g. a field declared
 * `RingBuffer<Float>`) -- it does NOT propagate through an abstract's own constructor, because
 * the abstract's type parameter is itself erased at that point (also verified empirically).
 * `@:multiType` sidesteps this entirely: it doesn't try to monomorphize a shared template
 * through the abstract at all, it picks between INDEPENDENTLY hand-written concrete
 * implementations at compile time via the `@:to` functions below, so `RingBufferFloatImpl` can
 * be a plain, non-generic, directly-`Float`-typed class -- trivially backed by a real
 * `haxe.ds.Vector<Float>` (a true `double[]`, confirmed via decompilation: `push`/`at` compile
 * to `push(D)`/`at(I)D`, unboxed argument and return) -- with zero monomorphization games.
 *
 * `RingBufferGenericImpl<T>` is the fallback for every other T (this codebase's `@:structInit`
 * pair classes, etc.) -- ordinary `Array<T>`-backed, boxed, but correct.
 *
 * Usage matches the plain-`Array<T>` rolling-window pattern this replaces as closely as
 * practical: `new RingBuffer(period)`, `.push(v)` (returns the evicted element once full, or
 * `null` while still filling -- see `push`'s own doc comment), `for (v in window)` (oldest to
 * newest, matching `for (v in plainArray)`), plus `window[i]` array-index sugar and `.length`
 * that a plain `Array<T>` field already had.
 *
 * ⚠️ **THE ONE PLACE IT DOES NOT MATCH: index order.** `window[i]` / `at(i)` count
 * NEWEST-first (`at(0)` is the most recent push), whereas an `Array` window's `window[0]` is
 * the OLDEST sample. `iterator()` is oldest-first, so indexed access and iteration run in
 * OPPOSITE directions within this very type. A mechanical `Array<Float>` -> `RingBuffer<Float>`
 * swap that leaves `window[i]` untouched therefore still compiles and silently reads the window
 * backwards in time -- which is exactly what happened on the first attempt at the bulk
 * migration (ALGORITHM_AUDIT.md §2): 16 indicators changed output, from sub-ULP summation-order
 * noise up to wholesale sign flips in running-peak drawdown ratios. **Use `oldest(i)` when
 * porting an `Array` window.**
 *
 * CAVEAT for hot scan loops (e.g. a min/max pass over the whole window every update -- the
 * single most common shape in this indicator library): `for (v in window)` boxes every element
 * regardless of T, EVEN for the Float fast path. Verified by decompilation: Haxe's `for..in`
 * codegen on the jvm target always normalizes a custom iterator through the `java.util.Iterator`
 * interface (`next():Ljava/lang/Object;`), so it boxes on the bridge method even when the
 * concrete iterator underneath has a real unboxed `next():Float` -- this is a target codegen
 * limitation, not something a smarter iterator class can route around. The genuinely unboxed
 * alternative (confirmed via decompilation: a clean primitive loop, zero boxing) is an indexed
 * scan: `for (i in 0...window.length) window.at(i)` (or `window[i]`) instead of `for (v in
 * window)`. Prefer the indexed form in any loop that runs every bar.
 */
@:multiType(@:followWithAbstracts T)
abstract RingBuffer<T>(IRingBuffer<T>) {
	public function new(capacity:Int);

	/**
	 * Appends `v`. Once the buffer is at capacity, evicts and returns the oldest element first
	 * (same "evict, then insert" order as the `if (window.length == period) window.shift();
	 * window.push(v);` pattern this replaces); returns `null` while the buffer is still filling,
	 * exactly matching that pattern's guard (nothing evicted before the window first fills).
	 */
	public inline function push(v:T):Null<T> return this.push(v);

	/**
	 * Value `i` slots back from the most recently pushed (0 = newest, length-1 = oldest).
	 *
	 * ⚠️ **This is the REVERSE of the `Array<T>` window it replaces**, where `window[0]` is the
	 * OLDEST sample. Because `@:arrayAccess` maps `buf[i]` here too, a migration that mechanically
	 * swaps `Array<Float>` for `RingBuffer<Float>` and leaves `window[i]` alone keeps compiling
	 * and silently reads the window BACKWARDS IN TIME. Note also that `iterator()` is
	 * oldest-first (it deliberately matches `Array`), so within this one type indexed access and
	 * iteration run in opposite directions — code that mixes them will disagree with itself.
	 *
	 * Verified empirically: pushing 1..6 into a capacity-4 buffer gives `at(i)`/`buf[i]` =
	 * `[6,5,4,3]` while `for (v in buf)` = `[3,4,5,6]`.
	 *
	 * When porting an existing `Array` window, use `oldest(i)` — it is the index order that
	 * pattern already assumes. Only reach for `at(i)` when you actually want "n bars ago"
	 * (which is usually what NEW code wants, hence this being the default).
	 */
	@:arrayAccess
	public inline function at(i:Int):T return this.at(i);

	/**
	 * Value at logical position `i` counting OLDEST-first — `oldest(0)` is the oldest retained
	 * sample, `oldest(length-1)` the newest. Identical indexing to the plain `Array<T>` +
	 * `shift()` window this type replaces, and to `iterator()`'s order.
	 *
	 * Exists so migrating an `Array` window is a mechanical `window[i]` → `window.oldest(i)`
	 * rather than a per-file reasoning exercise about whether that particular statistic happens
	 * to be order-invariant. (Some are — an R/S range over mean-centred deviations is unchanged
	 * by reversal — but most position-weighted ones, linear regressions, and running-peak
	 * drawdown scans are not, and the failure is silent.)
	 */
	public inline function oldest(i:Int):T return this.at(this.getLength() - 1 - i);

	public var length(get, never):Int;
	inline function get_length():Int return this.getLength();

	public var capacity(get, never):Int;
	inline function get_capacity():Int return this.getCapacity();

	public inline function isFull():Bool return this.getLength() == this.getCapacity();

	/** Oldest-to-newest, matching plain-Array `for (v in window)` iteration order. */
	public inline function iterator():Iterator<T> return this.iterator();

	@:to static inline function toFloatImpl(t:IRingBuffer<Float>, capacity:Int):RingBufferFloatImpl
		return new RingBufferFloatImpl(capacity);

	@:to static inline function toGenericImpl<T>(t:IRingBuffer<T>, capacity:Int):RingBufferGenericImpl<T>
		return new RingBufferGenericImpl<T>(capacity);
}

interface IRingBuffer<T> {
	function push(v:T):Null<T>;
	function at(i:Int):T;
	function getLength():Int;
	function getCapacity():Int;
	function iterator():Iterator<T>;
}

/** Float fast path: a plain (non-generic) class, so `Float` is concrete at ITS OWN definition
 * -- `data` is backed by a genuine primitive `double[]` on the JVM target, no monomorphization
 * required. On JS: `Float64Array` (JIT guide §3.5) instead of `Vector`→plain `Array`. */
class RingBufferFloatImpl implements IRingBuffer<Float> {
	#if js
	var data:js.lib.Float64Array;
	#else
	var data:haxe.ds.Vector<Float>;
	#end
	var head:Int = 0;
	var length:Int = 0;
	var capacity:Int;

	public function new(capacity:Int) {
		this.capacity = capacity;
		#if js
		data = new js.lib.Float64Array(capacity);
		#else
		data = new haxe.ds.Vector<Float>(capacity);
		#end
	}

	public function push(v:Float):Null<Float> {
		if (length < capacity) {
			data[length] = v;
			length++;
			return null;
		}
		var evicted = data[head];
		data[head] = v;
		head = (head + 1) % capacity;
		return evicted;
	}

	public function at(i:Int):Float {
		return data[(head + length - 1 - i + capacity) % capacity];
	}

	public function getLength():Int return length;
	public function getCapacity():Int return capacity;

	public function iterator():Iterator<Float> {
		var out = [for (i in 0...length) at(length - 1 - i)];
		return out.iterator();
	}
}

/** Generic fallback for every T that isn't Float (this codebase's `@:structInit` pair classes,
 * etc.) -- ordinary `Array<T>`-backed; boxed on the JVM target like any other generic
 * container, but correct for arbitrary element types. */
class RingBufferGenericImpl<T> implements IRingBuffer<T> {
	var data:Array<T>;
	var head:Int = 0;
	var length:Int = 0;
	var capacity:Int;

	public function new(capacity:Int) {
		this.capacity = capacity;
		data = [];
	}

	public function push(v:T):Null<T> {
		if (length < capacity) {
			data[length] = v;
			length++;
			return null;
		}
		var evicted = data[head];
		data[head] = v;
		head = (head + 1) % capacity;
		return evicted;
	}

	public function at(i:Int):T {
		return data[(head + length - 1 - i + capacity) % capacity];
	}

	public function getLength():Int return length;
	public function getCapacity():Int return capacity;

	public function iterator():Iterator<T> {
		var out = [for (i in 0...length) at(length - 1 - i)];
		return out.iterator();
	}
}
