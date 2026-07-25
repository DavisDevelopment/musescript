package musescript.evo;


/**
 * Structural digests for genomes and bool subtrees.
 *
 * Digest stays `Sha1(Serializer.run(...))` — byte-identical to `NmaCanonical` (TestNmaBijection).
 * The speed win is `StrategyGenome.keyCache` / `nodeCountCache`: elites and memo lookups stop
 * rebuilding the Dynamic tree on every touch. `Variation.copyGenome` omits the caches so splices
 * start cold (JIT guide §26).
 */
class Canonical {
	/** Telemetry: genome-key cache hits / misses since process start (or last `resetKeyStats`). */
	public static var keyHits:Int = 0;
	public static var keyMisses:Int = 0;

	public static function resetKeyStats():Void {
		keyHits = 0;
		keyMisses = 0;
	}

	public static function structuralKey(g:StrategyGenome):String {
		var cached = g.keyCache;
		if (cached != null) {
			keyHits++;
			return cached;
		}
		keyMisses++;
		var d = new StructuralDigest();
		digestGenome(d, g);
		var key = d.finish();
		g.keyCache = key;
		return key;
	}

	/** Structural digest of a bool subtree alone — P2 credit bank key (survives path changes). */
	public static function boolStructuralKey(n:BoolNode):String {
		var d = new StructuralDigest();
		digestBool(d, n);
		return d.finish();
	}

	// ---------- digest walk (token stream mirrored by NmaCanonical) ----------

	static function digestGenome(d:StructuralDigest, g:StrategyGenome):Void {
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

	static function digestSeries(d:StructuralDigest, n:SeriesNode):Void {
		switch (n) {
			case SPrice(f):
				d.tag("P".code);
				d.str(f);
			case SInd(name, field, window, src):
				d.tag("I".code);
				d.str(name);
				// Mirrors keySeries: a null source degrades to the bare price field, so both
				// forms emit a series token here and the arity stays fixed.
				if (src != null) digestSeries(d, src) else { d.tag("P".code); d.str(field); }
				d.int(window);
		}
	}

	static function digestScalar(d:StructuralDigest, n:ScalarNode):Void {
		switch (n) {
			case KConst(v):
				d.tag("K".code);
				d.float(Math.round(v * 1e9) / 1e9);
			case KParam(i):
				d.tag("R".code);
				d.int(i);
			case KFeature(name):
				d.tag("F".code);
				d.str(name);
			case KSeries(s):
				digestSeries(d, s);
			case KLookback(s, k):
				d.tag("L".code);
				digestSeries(d, s);
				d.int(k);
			case KArith(op, a, b):
				d.tag("A".code);
				d.str(op);
				digestScalar(d, a);
				digestScalar(d, b);
			// Transparent: a hole-wrapped subtree compiles to byte-identical MuseScript source as
			// its bare `inner` (see Expand.hx), so they must share ONE fitness-cache entry, not two.
			case KHole(inner):
				digestScalar(d, inner);
		}
	}

	static function digestBool(d:StructuralDigest, n:BoolNode):Void {
		switch (n) {
			case BCross(dir, a, b):
				d.tag("X".code);
				d.str(dir);
				digestSeries(d, a);
				digestSeries(d, b);
			case BCmp(op, a, b):
				d.tag("C".code);
				d.str(op);
				digestScalar(d, a);
				digestScalar(d, b);
			case BTrend(dir, s, w):
				d.tag("T".code);
				d.str(dir);
				digestSeries(d, s);
				d.int(w);
			case BAnd(a, b):
				d.tag("&".code);
				digestBool(d, a);
				digestBool(d, b);
			case BOr(a, b):
				d.tag("|".code);
				digestBool(d, a);
				digestBool(d, b);
			case BNot(a):
				d.tag("!".code);
				digestBool(d, a);
			case BHole(inner):
				digestBool(d, inner); // see digestScalar's KHole case
		}
	}

	/** Node count for a bool subtree (public wrapper over private `countBool`). */
	public static function boolNodeCount(n:BoolNode):Int return countBool(n);

	/** Nested Dynamic form of a genome key (also the input to `Serializer` inside `structuralKey`). */
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
		var cached = g.nodeCountCache;
		if (cached != null) return cached;
		var n = countBool(g.entryLong) + countBool(g.entryShort)
			+ countBool(g.exitLong) + countBool(g.exitShort) + countScalar(g.size);
		g.nodeCountCache = n;
		return n;
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
	 * `--speciation` fitness-sharing. Complementary to MAP-Elites' BEHAVIORAL niching.
	 */
	public static function shapeSignature(g:StrategyGenome):Map<String, Int> {
		var v = shapeVector(g);
		var m = new Map<String, Int>();
		for (i in 0...SHAPE_KINDS.length) if (v[i] != 0) m.set(SHAPE_KINDS[i], v[i]);
		return m;
	}

	/**
	 * `shapeSignature` in its native form: counts indexed by `SHAPE_KINDS` position, unboxed and
	 * fixed-length. Speciation compares these — Map<String,Int> is a HashMap with boxed keys
	 * (guide §25), so a Manhattan distance over it meant a fresh union map per pair.
	 */
	public static function shapeVector(g:StrategyGenome):haxe.ds.Vector<Int> {
		var v = new haxe.ds.Vector<Int>(SHAPE_KINDS.length);
		for (i in 0...v.length) v[i] = 0;
		inline function bump(i:Int):Void v[i] = v[i] + 1;
		function walkSeries(n:SeriesNode):Void {
			switch (n) {
				case SPrice(_): bump(K_SPRICE);
				case SInd(_, _, _, src): bump(K_SIND); if (src != null) walkSeries(src);
			}
		}
		function walkScalar(n:ScalarNode):Void {
			switch (n) {
				case KConst(_): bump(K_KCONST);
				case KParam(_): bump(K_KPARAM);
				case KFeature(_): bump(K_KFEATURE);
				case KSeries(s): bump(K_KSERIES); walkSeries(s);
				case KLookback(s, _): bump(K_KLOOKBACK); walkSeries(s);
				case KArith(_, a, b): bump(K_KARITH); walkScalar(a); walkScalar(b);
				case KHole(inner): bump(K_KHOLE); walkScalar(inner);
			}
		}
		function walkBool(n:BoolNode):Void {
			switch (n) {
				case BCross(_, a, b): bump(K_BCROSS); walkSeries(a); walkSeries(b);
				case BCmp(_, a, b): bump(K_BCMP); walkScalar(a); walkScalar(b);
				case BTrend(_, s, _): bump(K_BTREND); walkSeries(s);
				case BAnd(a, b): bump(K_BAND); walkBool(a); walkBool(b);
				case BOr(a, b): bump(K_BOR); walkBool(a); walkBool(b);
				case BNot(a): bump(K_BNOT); walkBool(a);
				case BHole(inner): bump(K_BHOLE); walkBool(inner);
			}
		}
		walkBool(g.entryLong);
		walkBool(g.entryShort);
		walkBool(g.exitLong);
		walkBool(g.exitShort);
		walkScalar(g.size);
		return v;
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

	/** `shapeDistance` over `shapeVector`s: same Manhattan number, no allocation, no hashing. */
	public static function shapeVectorDistance(a:haxe.ds.Vector<Int>, b:haxe.ds.Vector<Int>):Int {
		var d = 0;
		for (i in 0...a.length) {
			var diff = a[i] - b[i];
			d += diff < 0 ? -diff : diff;
		}
		return d;
	}

	/** Σ of a shape vector's counts. Because Manhattan distance is bounded below by the difference
	 * of the totals (`|Σa − Σb| ≤ Σ|aᵢ − bᵢ|`), this is an EXACT admissible prefilter. */
	public static function shapeVectorTotal(v:haxe.ds.Vector<Int>):Int {
		var s = 0;
		for (i in 0...v.length) s += v[i];
		return s;
	}

	/** Fixed declared order for `shapeVector`/`shapeFeatures`. */
	static var SHAPE_KINDS = ["BCross", "BCmp", "BTrend", "BAnd", "BOr", "BNot", "BHole",
		"KConst", "KParam", "KArith", "KSeries", "KLookback", "KFeature", "KHole", "SPrice", "SInd"];

	static inline var K_BCROSS = 0;
	static inline var K_BCMP = 1;
	static inline var K_BTREND = 2;
	static inline var K_BAND = 3;
	static inline var K_BOR = 4;
	static inline var K_BNOT = 5;
	static inline var K_BHOLE = 6;
	static inline var K_KCONST = 7;
	static inline var K_KPARAM = 8;
	static inline var K_KARITH = 9;
	static inline var K_KSERIES = 10;
	static inline var K_KLOOKBACK = 11;
	static inline var K_KFEATURE = 12;
	static inline var K_KHOLE = 13;
	static inline var K_SPRICE = 14;
	static inline var K_SIND = 15;

	/**
	 * `shapeSignature` turned into a fixed-length, SCALE-INVARIANT numeric feature vector, for
	 * `SurrogateModel`'s opt-in `--surrogate` fitness pre-filter.
	 */
	public static function shapeFeatures(g:StrategyGenome):Array<Float> {
		var sig = shapeVector(g);
		var n = nodeCount(g);
		var denom = n > 0 ? n : 1;
		var out = [for (i in 0...sig.length) sig[i] / denom];
		out.push(n / 50.0);
		out.push(g.params.length);
		return out;
	}
}