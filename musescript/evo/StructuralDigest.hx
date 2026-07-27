package musescript.evo;

/**
 * Streaming structural digest — the shared hash behind `Canonical` and `NmaCanonical`.
 *
 * Both classes used to key a subtree by building a nested `Dynamic` array mirror of it, running
 * that through `haxe.Serializer` to get a string, SHA-1ing the string and keeping 16 characters.
 * For a genome key, amortized behind `StrategyGenome.keyCache`, that is affordable. For
 * `boolStructuralKey` it is not: attribution keys every candidate site and every candidate donor
 * on every child of every generation and nothing caches the result, so the enum side paid a tree
 * of allocations, a reflective serialization pass and a cryptographic digest for each one. That
 * bookkeeping — not the ablation oracle it feeds — turned out to be where attribution's time
 * actually goes (measured: blind crossover 405 ms/gen, attributed-with-oracle-disabled 516).
 *
 * A structural key needs collision resistance, not preimage resistance, so the cryptographic
 * digest was never buying anything. This walks the tree once and mixes tokens straight into two
 * 32-bit FNV-1a lanes, allocating one small accumulator instead of a mirror tree and a string.
 * Output stays 16 hex characters, the same width as the SHA-1 prefix it replaces.
 *
 * PARITY. `Canonical` and `NmaCanonical` are pinned byte-identical by `TestNmaBijection`. They
 * hold because both emit the SAME token stream, which is a stronger guarantee than both happening
 * to build equal `Dynamic` mirrors: any token added on one side must be added on the other or the
 * differential test fails immediately.
 *
 * UNAMBIGUITY. Every node emits a `tag` and every tag has fixed arity, so structure is recoverable
 * from the stream and two different shapes cannot produce the same one. Variable-length pieces
 * (strings, the parameter list) emit their length first, which is what stops `name="ab"` from
 * colliding with two adjacent one-character fields.
 *
 * PORTABILITY. `mul32` is the 16-bit-split multiply rather than bare `*`. Haxe `Int` multiplication
 * wraps mod 2^32 on the JVM but is float multiplication on JS, where products above 2^53 silently
 * lose precision and the two targets would disagree. Splitting keeps every JS intermediate exactly
 * representable, and because reduction mod 2^32 commutes with `+` and `*`, reducing late (JS) and
 * reducing early (JVM) land on the same answer.
 *
 * «ἓν νῆμα διὰ πάντων· ὁ κόμβος οὐ λύεται.»
 */
class StructuralDigest {
	// FNV-1a 32-bit constants, written signed because these exceed Int32 range as positive
	// literals: offset basis 2166136261, prime 16777619.
	static inline var OFFSET1 = -2128831035;
	static inline var PRIME1 = 16777619;
	// Second lane: a different offset/prime pair so the two lanes are independent functions of
	// the same stream rather than one function twice.
	static inline var OFFSET2 = -1640531527; // 2654435769, the golden-ratio constant
	static inline var PRIME2 = -2048144777; // 0x85EBCA77

	var h1:Int;
	var h2:Int;

	public function new() {
		h1 = OFFSET1;
		h2 = OFFSET2;
	}

	/**
	 * Restore both lanes and the output words to their post-`new()` values, so one accumulator
	 * can key many subtrees in a row instead of one allocation per key. Hashing is untouched: a
	 * reset instance is indistinguishable from a fresh one.
	 */
	public inline function reset():StructuralDigest {
		h1 = OFFSET1;
		h2 = OFFSET2;
		outA = 0;
		outB = 0;
		return this;
	}

	/** Mix one 32-bit token into both lanes. */
	public inline function word(v:Int):StructuralDigest {
		h1 = mul32(h1 ^ v, PRIME1);
		// Perturb the second lane's input so identical tokens don't drive both lanes in step.
		h2 = mul32(h2 ^ (v ^ 0x5BF03635), PRIME2);
		return this;
	}

	/** Node-constructor marker. Distinct per constructor and of fixed arity. */
	public inline function tag(code:Int):StructuralDigest {
		return word(code);
	}

	public inline function int(v:Int):StructuralDigest {
		return word(v);
	}

	/** Length-prefixed so adjacent strings cannot be confused for one another. */
	public function str(s:String):StructuralDigest {
		if (s == null) return word(-1);
		word(s.length);
		for (i in 0...s.length) word(StringTools.fastCodeAt(s, i));
		return this;
	}

	/** IEEE-754 bit pattern, so `-0.0`, `0.0` and near-equal values stay distinguishable. */
	public function float(v:Float):StructuralDigest {
		var bits = haxe.io.FPHelper.doubleToI64(v);
		word(bits.low);
		return word(bits.high);
	}

	/** Avalanche both lanes into the digest's `outA`/`outB` fields — no String, no anon. */
	public var outA:Int = 0;
	public var outB:Int = 0;

	/** 16 lowercase hex characters: both lanes, avalanched. */
	public function finish():String {
		finishWords();
		return hex8(outA) + hex8(outB);
	}

	/** Same avalanche as `finish`, written into `outA`/`outB` instead of hex. */
	public inline function finishWords():StructuralDigest {
		outA = fmix32(h1);
		outB = fmix32(h2);
		return this;
	}

	/** Hex form of an already-finished word pair (keeps `Canonical`/`NmaCanonical` string keys). */
	public static inline function hexWords(a:Int, b:Int):String {
		return hex8(a) + hex8(b);
	}

	/** True when `s` is exactly 16 lowercase hex digits (a finished structural key). */
	public static function isHexKey(s:String):Bool {
		if (s == null || s.length != 16) return false;
		for (i in 0...16) {
			var c = StringTools.fastCodeAt(s, i);
			if (!((c >= 48 && c <= 57) || (c >= 97 && c <= 102))) return false;
		}
		return true;
	}

	/** Parse a 16-char hex structural key into avalanched digest lanes. */
	public static function wordsFromHexKey(key:String):{a:Int, b:Int} {
		return {
			a: parseHex8(key, 0),
			b: parseHex8(key, 8)
		};
	}

	/**
	 * Parse 8 hex digits as a raw 32-bit word. Must NOT use `Std.parseInt("0x...")`: values with
	 * the high bit set (e.g. `8df7a2e1`) exceed signed Int32 range and throw on the JVM target.
	 */
	static function parseHex8(s:String, off:Int):Int {
		var v = 0;
		var i = 0;
		while (i < 8) {
			var c = StringTools.fastCodeAt(s, off + i);
			var d = if (c >= 48 && c <= 57) c - 48
				else if (c >= 97 && c <= 102) c - 87
				else if (c >= 65 && c <= 70) c - 55
				else 0;
			v = (v << 4) | d;
			i++;
		}
		return v;
	}

	/** murmur3 finalizer — without it the low bits of an FNV lane are poorly mixed. */
	static inline function fmix32(h:Int):Int {
		h ^= h >>> 16;
		h = mul32(h, -2048144789); // 0x85EBCA6B
		h ^= h >>> 13;
		h = mul32(h, -1028477387); // 0xC2B2AE35
		h ^= h >>> 16;
		return h;
	}

	/** 32-bit multiply that agrees on JVM and JS (see the class note on PORTABILITY). */
	static inline function mul32(a:Int, b:Int):Int {
		var al = a & 0xFFFF;
		var ah = (a >>> 16) & 0xFFFF;
		var bl = b & 0xFFFF;
		var bh = (b >>> 16) & 0xFFFF;
		// Only the low 16 bits of the cross terms survive the shift, so reduce before shifting.
		var mid = (al * bh + ah * bl) & 0xFFFF;
		return ((al * bl) + (mid << 16)) | 0;
	}

	static inline function hex8(v:Int):String {
		return StringTools.hex(v, 8).toLowerCase();
	}
}
