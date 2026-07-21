package musescript.harness;

import musescript.runtime.MuseIter;
import musescript.runtime.IterResult;

/**
 * OHLCV feed as MuseIter<Bar>.
 */
class BarFeed implements MuseIter {
	var bars:Array<Bar>;
	var i:Int;

	public function new(bars:Array<Bar>) {
		this.bars = bars != null ? bars : [];
		this.i = 0;
	}

	public function next():IterResult<Dynamic> {
		if (i >= bars.length) return Done;
		return Value(bars[i++]);
	}

	public function reset():Void i = 0;

	public function length():Int return bars.length;

	public function all():Array<Bar> return bars;

	/**
	 * Portable 32-bit-wrapping multiply, via the `haxe.Int32` abstract's overloaded `*`
	 * operator (NOT raw `Int` `*`). This LCG's multiplier (1103515245, ~2^30) times a value up
	 * to 2^31 produces a product up to ~2^61, past JS Number's exact-integer range (2^53) --
	 * raw `Int` `*` on the JS target silently loses precision there (JS has no native 32-bit
	 * int; Haxe's Int on that target IS a Number), while a real-32-bit-int target (JVM, C++,
	 * ...) produces a mathematically DIFFERENT result via correct hardware overflow on the
	 * exact same source. Two Haxe targets given "the same seed" were silently generating
	 * different bars — found while cross-validating a JVM-compiled MuseInterp against JS.
	 * `haxe.Int32`'s `*` forces the correct 32-bit-wrapping product on every target (compiles
	 * to `Math.imul` on JS specifically to fix this exact class of bug), so the sequence is now
	 * actually portable, not just self-consistent within whichever target ran it.
	 */
	static inline function imul32(a:Int, b:Int):Int {
		var r:haxe.Int32 = (a : haxe.Int32) * (b : haxe.Int32);
		return r;
	}

	public static function synthetic(n:Int = 200, ?seed:Int = 1):BarFeed {
		var bars:Array<Bar> = [];
		var price = 100.0;
		var rng = seed;
		for (i in 0...n) {
			rng = (imul32(rng, 1103515245) + 12345) & 0x7fffffff;
			var noise = ((rng % 1000) / 1000.0 - 0.5) * 2.0;
			var o = price;
			var c = price * (1 + noise * 0.01);
			var h = Math.max(o, c) * 1.002;
			var l = Math.min(o, c) * 0.998;
			var v = 1000.0 + (rng % 500);
			bars.push({ open: o, high: h, low: l, close: c, volume: v, time: i * 60.0, index: i });
			price = c;
		}
		return new BarFeed(bars);
	}
}
