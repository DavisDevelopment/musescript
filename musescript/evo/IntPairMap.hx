package musescript.evo;

/**
 * Open-addressed `(Int,Int) → V` map with unboxed primitive key storage.
 *
 * JIT guide §25 (`evo/nma/JIT_AUTHORING_GUIDE.md`): on the JVM target `Map<Int,V>` is a thin
 * wrapper over `java.util.HashMap<Integer,V>`, so every `set`/`get`/`exists` boxes the key.
 * A two-level `IntMap<IntMap<V>>` therefore boxes *both* key components on every lookup and
 * store — trading String allocation for `Integer` boxing on the pop-memo hot path
 * (`NmaColumnCache.getWords`/`putWords`, thousands of calls per genome per generation).
 *
 * Keys live in parallel `haxe.ds.Vector<Int>` lanes (primitive `int[]` on JVM); values in a
 * parallel `Array<V>`. Empty slots are tracked by a `haxe.ds.Vector<Bool>` occupancy bitmap so
 * any 32-bit `(a,b)` pair — including `(0,0)` — is a valid key.
 *
 * Same discipline as `ParamMapping` and the primitive-friendly containers in
 * `indicators/GrowableVec.hx` / `RingBuffer.hx`: keep hot-path indices off boxed map APIs.
 */
class IntPairMap<V> {
	var keysA:haxe.ds.Vector<Int>;
	var keysB:haxe.ds.Vector<Int>;
	var values:Array<V>;
	var occupied:haxe.ds.Vector<Bool>;
	var count:Int = 0;
	var capacity:Int;

	public function new(?initialCapacity:Int = 16) {
		capacity = nextPow2(initialCapacity < 4 ? 4 : initialCapacity);
		alloc(capacity);
	}

	public inline function size():Int return count;

	public inline function exists(a:Int, b:Int):Bool {
		return findSlot(a, b) >= 0;
	}

	public function get(a:Int, b:Int):Null<V> {
		var i = findSlot(a, b);
		return i >= 0 ? values[i] : null;
	}

	public function set(a:Int, b:Int, v:V):Void {
		var i = findSlot(a, b);
		if (i >= 0) {
			values[i] = v;
			return;
		}
		i = -(i + 1);
		keysA[i] = a;
		keysB[i] = b;
		values[i] = v;
		occupied[i] = true;
		count++;
		if (count > ((capacity * 3) >> 2)) grow();
	}

	function alloc(n:Int):Void {
		keysA = new haxe.ds.Vector<Int>(n);
		keysB = new haxe.ds.Vector<Int>(n);
		values = [];
		values.resize(n);
		occupied = new haxe.ds.Vector<Bool>(n);
		for (i in 0...n) occupied[i] = false;
	}

	function grow():Void {
		var oldA = keysA;
		var oldB = keysB;
		var oldV = values;
		var oldO = occupied;
		var oldCap = capacity;
		capacity <<= 1;
		alloc(capacity);
		count = 0;
		for (i in 0...oldCap)
			if (oldO[i]) set(oldA[i], oldB[i], oldV[i]);
	}

	/** Linear-probing lookup. Returns slot index, or `-(emptySlot + 1)` on miss. */
	function findSlot(a:Int, b:Int):Int {
		var mask = capacity - 1;
		var idx = hash(a, b) & mask;
		while (occupied[idx]) {
			if (keysA[idx] == a && keysB[idx] == b) return idx;
			idx = (idx + 1) & mask;
		}
		return -(idx + 1);
	}

	static inline function hash(a:Int, b:Int):Int {
		return (a * 31 + b) | 0;
	}

	static function nextPow2(n:Int):Int {
		var p = 1;
		while (p < n) p <<= 1;
		return p;
	}
}
