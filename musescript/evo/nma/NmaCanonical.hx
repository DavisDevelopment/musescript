package musescript.evo.nma;

import musescript.evo.EvoParam;
import musescript.evo.StructuralDigest;
// Explicit module imports pull in each family's SECONDARY types (NmaSPrice, NmaKArith, NmaBHole,
// ...) -- same-package auto-import only brings each module's PRIMARY type into scope.
import musescript.evo.nma.NmaSeries;
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBool;

/**
 * NMA-native structural keying + node counting -- the reference implementation of the
 * kind-switch hot-walk pattern (`NmaNode`'s GraalVM dispatch note) and the identity half of P1's
 * memoization. Reproduces `musescript.evo.Canonical` EXACTLY (same nested-`Dynamic` key shape, same
 * `Sha1(Serializer(...))` digest, same transparent-hole / transparent-`KSeries` counting rules) but
 * sourced straight from the NMA tree via `switch (node.kind)` + typed `cast` -- so an evolution loop
 * running on the NMA working-copy can drive the existing `EvoCache`/`Fitness` structural-key caches
 * without a detour back through the enum form on every lookup.
 *
 * Parity is not asserted by inspection -- `TestNmaBijection` differential-tests it against
 * `Canonical` across fuzzed genomes: `NmaCanonical.structuralKey(fromEnum(g))` must equal
 * `Canonical.structuralKey(g)` for all g. The bijection is the free oracle (spec §6b).
 *
 * GraalVM shape: every walk here is a central `switch (n.kind)` (a `tableswitch` on the enum index,
 * monomorphic per case after the `cast`), NOT a virtual method dispatched over the 16 subclasses --
 * see `NmaNode`. No `Dynamic`/`Reflect` beyond the key arrays that mirror `Canonical`'s own (those
 * feed `haxe.Serializer` exactly as the enum side does; keeping them identical is what preserves the
 * digest). `nodeCount` allocates nothing.
 *
 * «στεφάνους πλέκει κισσός· μέθη σοφίαν δίδωσι.»
 */
class NmaCanonical {

	// ---------- structural key (byte-identical digest to Canonical) ----------

	public static function structuralKey(g:NmaGenome):String {
		var d = new StructuralDigest();
		digestGenome(d, g);
		return d.finish();
	}

	/** Content-addressed key for a bool subtree (pop-memo / credit). Lazily cached on the node. */
	public static function boolStructuralKey(n:NmaBool):String {
		ensureWordsBool(n);
		if (n.structuralKey == null)
			n.structuralKey = StructuralDigest.hexWords(n.structA, n.structB);
		return n.structuralKey;
	}

	public static function scalarStructuralKey(n:NmaScalar):String {
		ensureWordsScalar(n);
		if (n.structuralKey == null)
			n.structuralKey = StructuralDigest.hexWords(n.structA, n.structB);
		return n.structuralKey;
	}

	public static function seriesStructuralKey(n:NmaSeries):String {
		ensureWordsSeries(n);
		if (n.structuralKey == null)
			n.structuralKey = StructuralDigest.hexWords(n.structA, n.structB);
		return n.structuralKey;
	}

	/** Populate `structA`/`structB` without building the hex string. */
	public static inline function ensureWordsBool(n:NmaBool):Void {
		if (n.structReady) return;
		var d = new StructuralDigest();
		digestBool(d, n);
		cacheWords(n, d);
	}

	public static inline function ensureWordsScalar(n:NmaScalar):Void {
		if (n.structReady) return;
		var d = new StructuralDigest();
		digestScalar(d, n);
		cacheWords(n, d);
	}

	public static inline function ensureWordsSeries(n:NmaSeries):Void {
		if (n.structReady) return;
		var d = new StructuralDigest();
		digestSeries(d, n);
		cacheWords(n, d);
	}

	static function cacheWords(n:NmaNode, d:StructuralDigest):Void {
		d.finishWords();
		n.structA = d.outA;
		n.structB = d.outB;
		n.structReady = true;
	}

	// ---------- digest walk (token-for-token mirror of Canonical's) ----------

	static function digestGenome(d:StructuralDigest, g:NmaGenome):Void {
		d.tag("G".code);
		digestBool(d, g.entryLong);
		digestBool(d, g.entryShort);
		digestBool(d, g.exitLong);
		digestBool(d, g.exitShort);
		digestScalar(d, g.size);
		d.int(g.params.length);
		for (p in g.params) {
			d.str(p.name);
			d.float(p.defaultValue);
			d.float(p.min);
			d.float(p.max);
			d.float(p.step);
			d.str(p.tune);
		}
		d.str(g.name);
	}

	static function digestSeries(d:StructuralDigest, n:NmaSeries):Void {
		switch (n.kind) {
			case SPrice:
				d.tag("P".code);
				d.str((cast n : NmaSPrice).field);
			case SInd:
				var s = (cast n : NmaSInd);
				d.tag("I".code);
				d.str(s.name);
				if (s.src != null) digestSeries(d, s.src) else { d.tag("P".code); d.str(s.field); }
				d.int(s.window);
			default: throw 'NmaCanonical.digestSeries: non-series kind ${n.kind}';
		}
	}

	static function digestScalar(d:StructuralDigest, n:NmaScalar):Void {
		switch (n.kind) {
			case KConst:
				d.tag("K".code);
				d.float(Math.round((cast n : NmaKConst).v * 1e9) / 1e9);
			case KParam:
				d.tag("R".code);
				d.int((cast n : NmaKParam).idx);
			case KFeature:
				d.tag("F".code);
				d.str((cast n : NmaKFeature).name);
			case KSeries:
				digestSeries(d, (cast n : NmaKSeries).s);
			case KLookback:
				var l = (cast n : NmaKLookback);
				d.tag("L".code);
				digestSeries(d, l.s);
				d.int(l.n);
			case KArith:
				var a = (cast n : NmaKArith);
				d.tag("A".code);
				d.str(a.op);
				digestScalar(d, a.a);
				digestScalar(d, a.b);
			// Transparent, exactly as Canonical.digestScalar's KHole case.
			case KHole:
				digestScalar(d, (cast n : NmaKHole).inner);
			case KNp:
				var k = (cast n : NmaKNp);
				d.tag("Q".code); // match Canonical.digestScalar KNp
				d.str(k.op);
				digestSeries(d, k.a);
				d.int(k.window);
				if (k.b != null) digestSeries(d, k.b) else d.tag(0);
			case KPd:
				var p = (cast n : NmaKPd);
				d.tag("D".code); // match Canonical.digestScalar KPd
				d.str(p.op);
				d.str(p.pdKind);
				d.int(p.window);
				d.str(p.sym);
				d.int(p.syms != null ? p.syms.length : 0);
				if (p.syms != null) for (s in p.syms) d.str(s);
			default: throw 'NmaCanonical.digestScalar: non-scalar kind ${n.kind}';
		}
	}

	static function digestBool(d:StructuralDigest, n:NmaBool):Void {
		switch (n.kind) {
			case BCross:
				var c = (cast n : NmaBCross);
				d.tag("X".code);
				d.str(c.dir);
				digestSeries(d, c.a);
				digestSeries(d, c.b);
			case BCmp:
				var c = (cast n : NmaBCmp);
				d.tag("C".code);
				d.str(c.op);
				digestScalar(d, c.a);
				digestScalar(d, c.b);
			case BTrend:
				var t = (cast n : NmaBTrend);
				d.tag("T".code);
				d.str(t.dir);
				digestSeries(d, t.s);
				d.int(t.window);
			case BAnd:
				var a = (cast n : NmaBAnd);
				d.tag("&".code);
				digestBool(d, a.a);
				digestBool(d, a.b);
			case BOr:
				var o = (cast n : NmaBOr);
				d.tag("|".code);
				digestBool(d, o.a);
				digestBool(d, o.b);
			case BNot:
				d.tag("!".code);
				digestBool(d, (cast n : NmaBNot).a);
			case BHole:
				digestBool(d, (cast n : NmaBHole).inner); // transparent, see digestScalar's KHole
			default: throw 'NmaCanonical.digestBool: non-bool kind ${n.kind}';
		}
	}

	public static function genomeKey(g:NmaGenome):Dynamic {
		return [
			keyBool(g.entryLong), keyBool(g.entryShort),
			keyBool(g.exitLong), keyBool(g.exitShort),
			keyScalar(g.size),
			[for (p in g.params) [p.name, p.defaultValue, p.min, p.max, p.step, p.tune]],
			g.name
		];
	}

	static function keySeries(n:NmaSeries):Dynamic {
		return switch (n.kind) {
			case SPrice: ["P", (cast n : NmaSPrice).field];
			case SInd:
				var s = (cast n : NmaSInd);
				["I", s.name, s.src != null ? keySeries(s.src) : ["P", s.field], s.window];
			default: throw 'NmaCanonical.keySeries: non-series kind ${n.kind}';
		};
	}

	static function keyScalar(n:NmaScalar):Dynamic {
		return switch (n.kind) {
			case KConst: ["K", Math.round((cast n : NmaKConst).v * 1e9) / 1e9];
			case KParam: ["R", (cast n : NmaKParam).idx];
			case KFeature: ["F", (cast n : NmaKFeature).name];
			case KSeries: keySeries((cast n : NmaKSeries).s);
			case KLookback:
				var l = (cast n : NmaKLookback);
				["L", keySeries(l.s), l.n];
			case KArith:
				var a = (cast n : NmaKArith);
				["A", a.op, keyScalar(a.a), keyScalar(a.b)];
			// Transparent, exactly as Canonical.keyScalar's KHole case: a hole-wrapped subtree
			// compiles to byte-identical source as its bare inner, so they share ONE cache entry.
			case KHole: keyScalar((cast n : NmaKHole).inner);
			case KNp:
				var k = (cast n : NmaKNp);
				["Q", k.op, keySeries(k.a), k.window, k.b != null ? keySeries(k.b) : null];
			case KPd:
				var p = (cast n : NmaKPd);
				["D", p.op, p.pdKind, p.window, p.sym, p.syms != null ? p.syms.copy() : []];
			default: throw 'NmaCanonical.keyScalar: non-scalar kind ${n.kind}';
		};
	}

	static function keyBool(n:NmaBool):Dynamic {
		return switch (n.kind) {
			case BCross:
				var c = (cast n : NmaBCross);
				["X", c.dir, keySeries(c.a), keySeries(c.b)];
			case BCmp:
				var c = (cast n : NmaBCmp);
				["C", c.op, keyScalar(c.a), keyScalar(c.b)];
			case BTrend:
				var t = (cast n : NmaBTrend);
				["T", t.dir, keySeries(t.s), t.window];
			case BAnd:
				var a = (cast n : NmaBAnd);
				["&", keyBool(a.a), keyBool(a.b)];
			case BOr:
				var o = (cast n : NmaBOr);
				["|", keyBool(o.a), keyBool(o.b)];
			case BNot: ["!", keyBool((cast n : NmaBNot).a)];
			case BHole: keyBool((cast n : NmaBHole).inner); // transparent, see keyScalar's KHole
			default: throw 'NmaCanonical.keyBool: non-bool kind ${n.kind}';
		};
	}

	// ---------- node count (matches Canonical exactly, allocation-free) ----------

	public static function nodeCount(g:NmaGenome):Int {
		return countBool(g.entryLong) + countBool(g.entryShort)
			+ countBool(g.exitLong) + countBool(g.exitShort) + countScalar(g.size);
	}

	static function countSeries(n:NmaSeries):Int {
		return switch (n.kind) {
			case SPrice: 1;
			case SInd:
				var s = (cast n : NmaSInd);
				1 + (s.src != null ? countSeries(s.src) : 0);
			default: 0;
		};
	}

	static function countScalar(n:NmaScalar):Int {
		return switch (n.kind) {
			case KConst | KParam | KFeature: 1;
			case KSeries: countSeries((cast n : NmaKSeries).s);
			case KLookback: 1 + countSeries((cast n : NmaKLookback).s);
			case KArith:
				var a = (cast n : NmaKArith);
				1 + countScalar(a.a) + countScalar(a.b);
			// No +1: the wrapper is template scaffolding, not logical complexity (matches Canonical).
			case KHole: countScalar((cast n : NmaKHole).inner);
			case KNp:
				var k = (cast n : NmaKNp);
				1 + countSeries(k.a) + (k.b != null ? countSeries(k.b) : 0);
			case KPd: 1;
			default: 0;
		};
	}

	static function countBool(n:NmaBool):Int {
		return switch (n.kind) {
			case BCross:
				var c = (cast n : NmaBCross);
				1 + countSeries(c.a) + countSeries(c.b);
			case BCmp:
				var c = (cast n : NmaBCmp);
				1 + countScalar(c.a) + countScalar(c.b);
			case BTrend: 1 + countSeries((cast n : NmaBTrend).s);
			case BAnd:
				var a = (cast n : NmaBAnd);
				1 + countBool(a.a) + countBool(a.b);
			case BOr:
				var o = (cast n : NmaBOr);
				1 + countBool(o.a) + countBool(o.b);
			case BNot: 1 + countBool((cast n : NmaBNot).a);
			case BHole: countBool((cast n : NmaBHole).inner); // no +1, see countScalar's KHole
			default: 0;
		};
	}
}
