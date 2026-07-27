package musescript.evo;

/**
 * Growable ordered list of `(Int,Int)` pairs with unboxed primitive storage — the list
 * counterpart to `IntPairMap`.
 *
 * A 128-bit structural digest is two 32-bit lanes (`StructuralDigest.outA`/`outB`), and the
 * attribution path collects them by the handful: the donor keys of a candidate site, the site
 * keys a credit-bank entry was earned under, the subtree keys of one child. Both obvious ways to
 * hold such a collection lose on the JVM target. `Array<String>` of `hexWords(a, b)` re-introduces
 * exactly the String allocation `StructuralDigest` exists to delete — two `StringTools.hex` calls,
 * a `toLowerCase` and a concat per key, per candidate, per child, per generation. `Array<Int>`
 * avoids the strings but boxes every lane as `java.lang.Integer` (JIT guide §3.1), and `for..in`
 * over it boxes again on the iterator bridge (§3.3).
 *
 * So the pairs live interleaved in one `haxe.ds.Vector<Int>` — a genuine primitive `int[]` on JVM —
 * with `buf[2i]` the first lane and `buf[2i+1]` the second, grown by capacity-doubling over
 * `Vector.blit` (`System.arraycopy`, a native handle copy) the way `GrowableVec` does. Every
 * internal scan is an indexed `while`, and `clear()` keeps the buffer so a per-generation list is
 * allocated once and refilled rather than rebuilt.
 *
 * Lookups are a linear scan on purpose: these lists hold tens of entries, where scanning two
 * primitive lanes beats a hash probe that has to box before it can even start (same reasoning as
 * `Variation.ParamMapping`, JIT guide §25). Reach for `IntPairMap` when the population grows or a
 * value needs to hang off the key.
 *
 * «δύο λαμπάδες ἐν ἑνὶ νήματι· ὁ ἀριθμὸς ὀνόματος οὐ δεῖται.»
 */
class IntPairList {
	/** Pairs interleaved: `buf[2i]` = a, `buf[2i+1]` = b. Length is always even. */
	var buf:haxe.ds.Vector<Int>;

	/** Count of PAIRS in use, not of ints — `len << 1` is the live prefix of `buf`. */
	var len:Int = 0;

	public function new(?capacityPairs:Int = 8) {
		var c = capacityPairs != null && capacityPairs > 0 ? capacityPairs : 8;
		buf = new haxe.ds.Vector<Int>(c << 1);
	}

	/** Number of PAIRS, not ints. */
	public var length(get, never):Int;

	inline function get_length():Int return len;

	/** Appends `(a,b)`, doubling the backing store if it is full. */
	public inline function push(a:Int, b:Int):Void {
		if ((len << 1) >= buf.length) grow();
		var i = len << 1;
		buf[i] = a;
		buf[i + 1] = b;
		len++;
	}

	/** First lane of pair `i`. */
	public inline function a(i:Int):Int return buf[i << 1];

	/** Second lane of pair `i`. */
	public inline function b(i:Int):Int return buf[(i << 1) + 1];

	/** Drops every pair but keeps the buffer, so the next generation refills instead of reallocating. */
	public inline function clear():Void {
		len = 0;
	}

	/** Linear scan; `-1` when absent. Ordered, so `(a,b)` and `(b,a)` are different pairs. */
	public function indexOfPair(a:Int, b:Int):Int {
		var i = 0;
		while (i < len) {
			var j = i << 1;
			if (buf[j] == a && buf[j + 1] == b) return i;
			i++;
		}
		return -1;
	}

	public function containsPair(a:Int, b:Int):Bool {
		return indexOfPair(a, b) >= 0;
	}

	/** Independent copy sharing no storage with the original. */
	public function copy():IntPairList {
		var out = new IntPairList(len > 0 ? len : 1);
		haxe.ds.Vector.blit(buf, 0, out.buf, 0, len << 1);
		out.len = len;
		return out;
	}

	/** Debugging only — allocates the strings this class exists to avoid. */
	public function toString():String {
		var sb = new StringBuf();
		sb.add("IntPairList[");
		sb.add(len);
		sb.add(":");
		var i = 0;
		while (i < len) {
			var j = i << 1;
			sb.add(" (");
			sb.add(buf[j]);
			sb.add(",");
			sb.add(buf[j + 1]);
			sb.add(")");
			i++;
		}
		sb.add("]");
		return sb.toString();
	}

	function grow():Void {
		var next = new haxe.ds.Vector<Int>(buf.length > 0 ? buf.length << 1 : 16);
		haxe.ds.Vector.blit(buf, 0, next, 0, buf.length);
		buf = next;
	}
}
