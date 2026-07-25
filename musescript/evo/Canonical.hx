package musescript.evo;

import haxe.crypto.Sha1;

class Canonical {
	public static function structuralKey(g:StrategyGenome):String {
		return Sha1.encode(haxe.Serializer.run(genomeKey(g))).substr(0, 16);
	}

	public static function genomeKey(g:StrategyGenome):Dynamic {
		return [
			keyBool(g.entryLong), keyBool(g.entryShort),
			keyBool(g.exitLong), keyBool(g.exitShort),
			keyScalar(g.size),
			[for (p in g.params) [p.name, p.defaultValue, p.min, p.max, p.step, p.tune]],
			g.name
		];
	}

	static function keySeries(n:SeriesNode):Dynamic {
		return switch (n) {
			case SPrice(f): ["P", f];
			case SInd(name, field, window, src):
				["I", name, src != null ? keySeries(src) : ["P", field], window];
		};
	}

	static function keyScalar(n:ScalarNode):Dynamic {
		return switch (n) {
			case KConst(v): ["K", Math.round(v * 1e9) / 1e9];
			case KParam(i): ["R", i];
			case KFeature(name): ["F", name];
			case KSeries(s): keySeries(s);
			case KLookback(s, k): ["L", keySeries(s), k];
			case KArith(op, a, b):
				var ka = keyScalar(a);
				var kb = keyScalar(b);
				["A", op, ka, kb];
			// Transparent: a hole-wrapped subtree compiles to byte-identical MuseScript source as
			// its bare `inner` (see Expand.hx), so they must share ONE fitness-cache entry, not two.
			case KHole(inner): keyScalar(inner);
		};
	}

	static function keyBool(n:BoolNode):Dynamic {
		return switch (n) {
			case BCross(dir, a, b): ["X", dir, keySeries(a), keySeries(b)];
			case BCmp(op, a, b): ["C", op, keyScalar(a), keyScalar(b)];
			case BTrend(dir, s, w): ["T", dir, keySeries(s), w];
			case BAnd(a, b): ["&", keyBool(a), keyBool(b)];
			case BOr(a, b): ["|", keyBool(a), keyBool(b)];
			case BNot(a): ["!", keyBool(a)];
			case BHole(inner): keyBool(inner); // see keyScalar's KHole case
		};
	}

	public static function nodeCount(g:StrategyGenome):Int {
		return countBool(g.entryLong) + countBool(g.entryShort)
			+ countBool(g.exitLong) + countBool(g.exitShort) + countScalar(g.size);
	}

	static function countSeries(n:SeriesNode):Int {
		return switch (n) {
			case SPrice(_): 1;
			case SInd(_, _, _, src): 1 + (src != null ? countSeries(src) : 0);
		};
	}

	static function countScalar(n:ScalarNode):Int {
		return switch (n) {
			case KConst(_) | KParam(_): 1;
			case KFeature(_): 1;
			case KSeries(s): countSeries(s);
			case KLookback(s, _): 1 + countSeries(s);
			case KArith(_, a, b): 1 + countScalar(a) + countScalar(b);
			// No +1: the wrapper is template scaffolding, not logical complexity -- parsimony
			// pressure shouldn't penalize a genome for being templated.
			case KHole(inner): countScalar(inner);
		};
	}

	static function countBool(n:BoolNode):Int {
		return switch (n) {
			case BCross(_, a, b): 1 + countSeries(a) + countSeries(b);
			case BCmp(_, a, b): 1 + countScalar(a) + countScalar(b);
			case BTrend(_, s, _): 1 + countSeries(s);
			case BAnd(a, b) | BOr(a, b): 1 + countBool(a) + countBool(b);
			case BNot(a): 1 + countBool(a);
			case BHole(inner): countBool(inner); // see countScalar's KHole case
		};
	}

	/**
	 * Structural "species" fingerprint -- a histogram of node-constructor kinds across the whole
	 * genome (entryLong/entryShort/exitLong/exitShort/size), for CorpusEvoRun's opt-in
	 * `--speciation` fitness-sharing (see this session's neuroevolution-inspired-upgrades plan).
	 * Complementary to MAP-Elites' BEHAVIORAL niching (MapElites.hx) -- this is the STRUCTURAL
	 * axis: two genomes with wildly different shapes that happen to trade similarly land in the
	 * same MAP-Elites cell but different species, and vice versa. Deliberately coarse (constructor
	 * KIND counts, not full tree-edit-distance) -- cheap enough to compute for every unique genome
	 * every generation.
	 */
	public static function shapeSignature(g:StrategyGenome):Map<String, Int> {
		var m = new Map<String, Int>();
		function bump(k:String):Void m.set(k, (m.exists(k) ? m.get(k) : 0) + 1);
		function walkSeries(n:SeriesNode):Void {
			switch (n) {
				case SPrice(_): bump("SPrice");
				case SInd(_, _, _, src): bump("SInd"); if (src != null) walkSeries(src);
			}
		}
		function walkScalar(n:ScalarNode):Void {
			switch (n) {
				case KConst(_): bump("KConst");
				case KParam(_): bump("KParam");
				case KFeature(_): bump("KFeature");
				case KSeries(s): bump("KSeries"); walkSeries(s);
				case KLookback(s, _): bump("KLookback"); walkSeries(s);
				case KArith(_, a, b): bump("KArith"); walkScalar(a); walkScalar(b);
				case KHole(inner): bump("KHole"); walkScalar(inner);
			}
		}
		function walkBool(n:BoolNode):Void {
			switch (n) {
				case BCross(_, a, b): bump("BCross"); walkSeries(a); walkSeries(b);
				case BCmp(_, a, b): bump("BCmp"); walkScalar(a); walkScalar(b);
				case BTrend(_, s, _): bump("BTrend"); walkSeries(s);
				case BAnd(a, b): bump("BAnd"); walkBool(a); walkBool(b);
				case BOr(a, b): bump("BOr"); walkBool(a); walkBool(b);
				case BNot(a): bump("BNot"); walkBool(a);
				case BHole(inner): bump("BHole"); walkBool(inner);
			}
		}
		walkBool(g.entryLong);
		walkBool(g.entryShort);
		walkBool(g.exitLong);
		walkBool(g.exitShort);
		walkScalar(g.size);
		return m;
	}

	/** Manhattan distance between two shape signatures -- the compatibility measure `--speciation`
	 * groups genomes by (see CorpusEvoRun.hx). Symmetric; treats a kind missing from one side as 0. */
	public static function shapeDistance(a:Map<String, Int>, b:Map<String, Int>):Int {
		var seen = new Map<String, Bool>();
		for (k in a.keys()) seen.set(k, true);
		for (k in b.keys()) seen.set(k, true);
		var d = 0;
		for (k in seen.keys()) {
			var av = a.exists(k) ? a.get(k) : 0;
			var bv = b.exists(k) ? b.get(k) : 0;
			d += Std.int(Math.abs(av - bv));
		}
		return d;
	}

	/** Fixed declared order for `shapeFeatures` below -- every node-constructor kind
	 * `shapeSignature` can ever bump, so the resulting vector is the SAME length/meaning for every
	 * genome regardless of what it actually contains (a kind it doesn't use just reads 0). */
	static var SHAPE_KINDS = ["BCross", "BCmp", "BTrend", "BAnd", "BOr", "BNot", "BHole",
		"KConst", "KParam", "KArith", "KSeries", "KLookback", "KFeature", "KHole", "SPrice", "SInd"];

	/**
	 * `shapeSignature` turned into a fixed-length, SCALE-INVARIANT numeric feature vector, for
	 * `SurrogateModel`'s opt-in `--surrogate` fitness pre-filter (see this session's surrogate-
	 * model plan). Each of `SHAPE_KINDS`' counts is normalized to a FRACTION of `nodeCount` (not
	 * the raw count) -- a 10-node and a 40-node genome with the same internal proportions produce
	 * similar vectors this way, which a raw-count vector wouldn't; two more scalar features are
	 * appended: `nodeCount` itself (loosely normalized, `/50.0`, so it stays roughly `0..1`-ish for
	 * a typical genome) and `params.length` (bare, params are rarely more than a handful). Always
	 * `SHAPE_KINDS.length + 2` entries long.
	 */
	public static function shapeFeatures(g:StrategyGenome):Array<Float> {
		var sig = shapeSignature(g);
		var n = nodeCount(g);
		var denom = n > 0 ? n : 1;
		var out = [for (k in SHAPE_KINDS) (sig.exists(k) ? sig.get(k) : 0) / denom];
		out.push(n / 50.0);
		out.push(g.params.length);
		return out;
	}
}
