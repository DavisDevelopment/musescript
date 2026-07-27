package musescript.evo.nma;

import haxe.ds.Vector;
import musescript.indicators.GrowableVec;
import musescript.evo.EvoLock;
import musescript.evo.StructuralDigest;

/**
 * Bit-packed trading signal for a genome: the three boolean columns `OrderSim` actually reacts to,
 * one bit per bar, plus a digest over them.
 *
 * WHY THIS IS AN EXACT IDENTITY, not a heuristic. `NmaFitness.runPrepared`'s loop reads exactly
 * five things per bar: `entryLong`, `entryShort`, `exitLong || exitShort`, the `size` scalar, and
 * the bar itself. Everything else it touches -- `positionSize()`, cash, the equity curve -- is
 * internal state evolving deterministically from those inputs. So two genomes that agree on these
 * columns over the same tape cannot produce different fills, different equity or different Sharpe,
 * regardless of how differently their trees are shaped. Structural keys miss that: `x > y` and
 * `!(x <= y)` are different trees and the same strategy.
 *
 * Two details make the identity tighter than the obvious encoding:
 *
 *  - `exitLong` and `exitShort` are folded with OR, because the loop only ever asks for their
 *    disjunction. Two genomes that disagree about WHICH exit fired, while agreeing that one did,
 *    are the same strategy and should collide.
 *  - `size` is mixed only at bars where an entry can fire. Its value is unobservable anywhere else,
 *    so hashing the whole column would split genomes that differ only in dead positions. This
 *    stays conservative: a bar where an entry bit is set but `positionSize()` happens to suppress
 *    the submit still contributes, since that suppression is not knowable before the run.
 *
 * The packing is also the natural substrate for behavioral distance -- `hamming` over two of these
 * is a real signal-level metric, unlike descriptor-space distance, and it exists for genomes that
 * never trade at all.
 *
 * «πολλαὶ μορφαί, μία σφραγίς.»
 */
class NmaSignalPack {
	/** Bars per packed word. `Int` is 32-bit on every target this runs on. */
	public static inline var BITS_PER_WORD = 32;

	public static inline function wordCount(n:Int):Int {
		return (n + 31) >> 5;
	}

	/** `v.at(i) >= 0.5` for each bar, packed low-bit-first. Threshold matches the sim loop. */
	public static function packBool(v:GrowableVec<Float>, n:Int):Vector<Int> {
		var w = new Vector<Int>(wordCount(n));
		for (k in 0...w.length) w[k] = 0;
		var i = 0;
		while (i < n) {
			if (v.at(i) >= 0.5) w[i >> 5] |= 1 << (i & 31);
			i++;
		}
		return w;
	}

	/** Packed `a || b` -- the only form of the exit pair the sim loop ever reads. */
	public static function packOr(a:GrowableVec<Float>, b:GrowableVec<Float>, n:Int):Vector<Int> {
		var w = new Vector<Int>(wordCount(n));
		for (k in 0...w.length) w[k] = 0;
		var i = 0;
		while (i < n) {
			if (a.at(i) >= 0.5 || b.at(i) >= 0.5) w[i >> 5] |= 1 << (i & 31);
			i++;
		}
		return w;
	}

	public static inline function bitAt(w:Vector<Int>, i:Int):Bool {
		return ((w[i >> 5] >>> (i & 31)) & 1) != 0;
	}

	/**
	 * Signature of the five columns the sim loop reads. Equal signatures imply an identical
	 * `OrderSim` run on the same tape and cost settings (see the class note).
	 */
	public static function signature(entryLong:Vector<Int>, entryShort:Vector<Int>, exit:Vector<Int>,
			size:GrowableVec<Float>, n:Int):String {
		var d = new StructuralDigest();
		d.int(n);
		mix(d, entryLong);
		mix(d, entryShort);
		mix(d, exit);
		// Size is only observable where an entry bit is set; see the class note.
		var i = 0;
		while (i < n) {
			if (bitAt(entryLong, i) || bitAt(entryShort, i)) {
				d.int(i);
				d.float(size.at(i));
			}
			i++;
		}
		return d.finish();
	}

	/**
	 * Stream the five sim-visible columns into `d` without allocating packed `Vector`s — the
	 * memo hot path. Token stream matches `signature(packBool…)` so probe strings and memo words
	 * stay one identity.
	 */
	public static function mixColumns(d:StructuralDigest, entryLong:GrowableVec<Float>,
			entryShort:GrowableVec<Float>, exitLong:GrowableVec<Float>, exitShort:GrowableVec<Float>,
			size:GrowableVec<Float>, n:Int):Void {
		d.int(n);
		mixPackedBool(d, entryLong, n);
		mixPackedBool(d, entryShort, n);
		mixPackedOr(d, exitLong, exitShort, n);
		var i = 0;
		while (i < n) {
			if (entryLong.at(i) >= 0.5 || entryShort.at(i) >= 0.5) {
				d.int(i);
				d.float(size.at(i));
			}
			i++;
		}
	}

	static function mixPackedBool(d:StructuralDigest, v:GrowableVec<Float>, n:Int):Void {
		var wc = wordCount(n);
		d.int(wc);
		var k = 0;
		while (k < wc) {
			var word = 0;
			var base = k << 5;
			var lim = base + 32;
			if (lim > n) lim = n;
			var i = base;
			while (i < lim) {
				if (v.at(i) >= 0.5) word |= 1 << (i & 31);
				i++;
			}
			d.int(word);
			k++;
		}
	}

	static function mixPackedOr(d:StructuralDigest, a:GrowableVec<Float>, b:GrowableVec<Float>, n:Int):Void {
		var wc = wordCount(n);
		d.int(wc);
		var k = 0;
		while (k < wc) {
			var word = 0;
			var base = k << 5;
			var lim = base + 32;
			if (lim > n) lim = n;
			var i = base;
			while (i < lim) {
				if (a.at(i) >= 0.5 || b.at(i) >= 0.5) word |= 1 << (i & 31);
				i++;
			}
			d.int(word);
			k++;
		}
	}

	static function mix(d:StructuralDigest, w:Vector<Int>):Void {
		d.int(w.length);
		for (k in 0...w.length) d.int(w[k]);
	}

	/** Set bits, for duty-cycle style descriptors. */
	public static function popcount(w:Vector<Int>):Int {
		var total = 0;
		for (k in 0...w.length) total += bits32(w[k]);
		return total;
	}

	/** Differing bars between two equal-length packings -- signal-space behavioral distance. */
	public static function hamming(a:Vector<Int>, b:Vector<Int>):Int {
		var m = a.length < b.length ? a.length : b.length;
		var total = 0;
		for (k in 0...m) total += bits32(a[k] ^ b[k]);
		return total;
	}

	/** SWAR popcount: pairs, nibbles, bytes, then one multiply to sum the bytes. */
	static inline function bits32(v:Int):Int {
		var x = v;
		x = x - ((x >>> 1) & 0x55555555);
		x = (x & 0x33333333) + ((x >>> 2) & 0x33333333);
		x = (x + (x >>> 4)) & 0x0F0F0F0F;
		// Multiplying by 0x01010101 accumulates the four byte counts into the top byte. Written as
		// shifts because Haxe `Int` multiply is float multiply on JS, where this product overflows.
		x = x + (x >>> 8);
		x = x + (x >>> 16);
		return x & 0x3F;
	}
}