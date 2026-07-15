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
		state = Std.int((state * 1103515245 + 12345) % 2147483648);
		if (state < 0) state = -state;
		return n == 0 ? 0 : state % n;
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
