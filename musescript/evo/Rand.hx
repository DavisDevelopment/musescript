package musescript.evo;

/** Deterministic LCG for reproducible evolution proofs. */
class Rand {
	public var seed:Int;
	var state:Int;

	public function new(seed:Int) {
		this.seed = seed;
		this.state = seed;
	}

	public function int(n:Int):Int {
		state = (imul32(state, 1103515245) + 12345) & 0x7fffffff;
		return n == 0 ? 0 : state % n;
	}

	/**
	 * Portable 32-bit-wrapping multiply, via the `haxe.Int32` abstract's overloaded `*`
	 * operator (NOT raw `Int` `*`) -- see musescript.harness.BarFeed.imul32 for the full
	 * writeup. Same LCG, same bug class: on JS, `Int` is a plain Number so raw `*` silently
	 * loses precision once the product exceeds 2^53, while a real-32-bit-int target (JVM,
	 * C++, ...) overflows correctly on the exact same source -- two targets given "the same
	 * seed" would silently diverge. `haxe.Int32`'s `*` forces the same 32-bit-wrapping
	 * product on every target.
	 */
	static inline function imul32(a:Int, b:Int):Int {
		var r:haxe.Int32 = (a : haxe.Int32) * (b : haxe.Int32);
		return r;
	}

	public function float():Float {
		return int(100000) / 100000.0;
	}

	public function bool():Bool {
		return int(2) == 0;
	}

	public function pick<T>(xs:Array<T>):T {
		return xs[int(xs.length)];
	}
}
