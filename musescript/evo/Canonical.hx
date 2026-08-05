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

	/** Avalanched digest lanes for a bool subtree — P2 credit bank key without hex allocation. */
	public static function boolStructuralWords(n:BoolNode):{a:Int, b:Int} {
		var d = new StructuralDigest();
		digestBool(d, n);
		d.finishWords();
		return { a: d.outA, b: d.outB };
	}

	/**
	 * Append a bool subtree's digest lanes to `out`, reusing `d` across the whole batch.
	 *
	 * Attribution keys every site of every attributed child and every donor it ranks, so the
	 * anon `{a, b}` of `boolStructuralWords` and the hex of `boolStructuralKey` are both paid
	 * per node rather than per generation. This form allocates neither (JIT guide §3.1).
	 */
	public static function boolStructuralInto(out:IntPairList, n:BoolNode, d:StructuralDigest):Void {
		d.reset();
		digestBool(d, n);
		d.finishWords();
		out.push(d.outA, d.outB);
	}

	/** `boolStructuralInto` over a batch — one digest, one list, no strings. */
	public static function boolStructuralKeysOf(nodes:Array<BoolNode>):IntPairList {
		var out = new IntPairList(nodes.length);
		var d = new StructuralDigest();
		var i = 0;
		while (i < nodes.length) {
			boolStructuralInto(out, nodes[i], d);
			i++;
		}
		return out;
	}

	/** Structural digest of a bool subtree alone — P2 credit bank key (survives path changes). */
	public static function boolStructuralKey(n:BoolNode):String {
		var w = boolStructuralWords(n);
		return StructuralDigest.hexWords(w.a, w.b);
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
		digestReferencedProjections(d, g);
		digestPanelAction(d, g);
	}

	/**
	 * Digest the panel-action template when present. Absense is byte-identical to pre-v1 keys
	 * (same contract as unreferenced projections). Present templates change Expand source, so
	 * they must differentiate fitness / archive keys.
	 */
	static function digestPanelAction(d:StructuralDigest, g:StrategyGenome):Void {
		if (g.panelAction == null) return;
		d.tag("@".code);
		switch (g.panelAction) {
			case PABuy(sym):
				d.str("buy");
				d.str(sym);
			case PARebalance(syms):
				d.str("rebal");
				d.int(syms.length);
				for (s in syms) d.str(s);
			case PATargetWeight(sym):
				d.str("tw");
				d.str(sym);
			case PABagScanTop(kind, window, topK, syms):
				d.str("bagscan");
				d.str(kind);
				d.int(window);
				d.int(topK);
				d.int(syms.length);
				for (s in syms) d.str(s);
			case PABagRankWeights(kind, window, syms):
				d.str("bagrw");
				d.str(kind);
				d.int(window);
				d.int(syms.length);
				for (s in syms) d.str(s);
		}
	}

	/**
	 * Digest the DEFINITIONS of projections the policy references (name, kind, horizon, samples,
	 * seed, sampler) — two genomes that reference the same `proj_0` but define it with a different
	 * sampler/seed render to different source and MUST NOT share a fitness-cache entry. Unreferenced
	 * projections are not rendered (Expand skips them), so they are not digested either — preserving
	 * the "declared-but-unread projection = identical key" contract. Appended only when present, so a
	 * projection-free genome's digest is byte-identical to before projections existed.
	 */
	static function digestReferencedProjections(d:StructuralDigest, g:StrategyGenome):Void {
		if (g.projections == null || g.projections.length == 0)
			return;
		var refs = referencedProjNames(g);
		for (p in g.projections) {
			if (!refs.exists(p.name))
				continue;
			d.tag("Q".code);
			d.str(p.name);
			d.str(Std.string(p.kind));
			d.int(p.horizon);
			d.int(p.samples);
			d.int(p.seed);
			switch (p.sampler) {
				case PSPoint(node):
					d.tag("p".code);
					digestSeries(d, node);
				case PSNoise(base, vol, model):
					d.tag("n".code);
					digestSeries(d, base);
					digestScalar(d, vol);
					d.str(Std.string(model));
				case PSHost(kind):
					d.tag("h".code);
					d.str(kind);
					digestPhiDeltas(d, p.phiDeltas);
			}
		}
	}

	/** Sorted key→value digest so Map iteration order cannot fork structural keys. */
	static function digestPhiDeltas(d:StructuralDigest, deltas:Null<Map<String, Float>>):Void {
		if (deltas == null) return;
		var keys = [for (k in deltas.keys()) k];
		keys.sort(Reflect.compare);
		for (k in keys) {
			d.tag("d".code);
			d.str(k);
			d.float(deltas.get(k));
		}
	}

	/** Names of projections referenced by an `SProj` anywhere across the five policy roots. */
	static function referencedProjNames(g:StrategyGenome):Map<String, Bool> {
		var m = new Map<String, Bool>();
		function ws(n:SeriesNode):Void switch (n) {
			case SPrice(_):
			case SInd(_, _, _, src): if (src != null) ws(src);
			case SProj(name, _): m.set(name, true);
			case SPanel(_, _, _, _):
		}
		function wsc(n:ScalarNode):Void switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _):
			case KSeries(s): ws(s);
			case KLookback(s, _): ws(s);
			case KNp(_, a, _, b):
				ws(a);
				if (b != null) ws(b);
			case KArith(_, a, b): wsc(a); wsc(b);
			case KHole(inner): wsc(inner);
		}
		function wb(n:BoolNode):Void switch (n) {
			case BCross(_, a, b): ws(a); ws(b);
			case BCmp(_, a, b): wsc(a); wsc(b);
			case BTrend(_, s, _): ws(s);
			case BAnd(a, b) | BOr(a, b): wb(a); wb(b);
			case BNot(a): wb(a);
			case BHole(inner): wb(inner);
				case BFeature(_): // opaque leaf: no structured children to walk
		}
		wb(g.entryLong);
		wb(g.entryShort);
		wb(g.exitLong);
		wb(g.exitShort);
		wsc(g.size);
		return m;
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
			case SProj(name, field):
				d.tag("J".code);
				d.str(name);
				d.str(field);
			case SPanel(kind, sym, field, window):
				// "N" — panel (avoid P/I/J and Lookback's L)
				d.tag("N".code);
				d.str(kind);
				d.str(sym);
				d.str(field != null ? field : "");
				d.int(window != null ? window : 0);
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
			case KNp(op, a, window, b):
				d.tag("Q".code); // NP (avoid N=panel)
				d.str(op);
				digestSeries(d, a);
				d.int(window);
				if (b != null) digestSeries(d, b) else d.tag(0);
			case KPd(op, kind, window, sym, syms):
				d.tag("D".code); // PD
				d.str(op);
				d.str(kind);
				d.int(window);
				d.str(sym);
				d.int(syms != null ? syms.length : 0);
				if (syms != null) for (s in syms) d.str(s);
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
			case BFeature(src):
				d.tag("F".code);
				d.str(src);
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
			case SProj(name, field): ["J", name, field];
			case SPanel(kind, sym, field, window):
				["N", kind, sym, field != null ? field : "", window != null ? window : 0];
		};
	}

	static function keyScalar(n:ScalarNode):Dynamic {
		return switch (n) {
			case KConst(v): ["K", Math.round(v * 1e9) / 1e9];
			case KParam(i): ["R", i];
			case KFeature(name): ["F", name];
			case KSeries(s): keySeries(s);
			case KLookback(s, k): ["L", keySeries(s), k];
			case KNp(op, a, window, b):
				["Q", op, keySeries(a), window, b != null ? keySeries(b) : null];
			case KPd(op, kind, window, sym, syms):
				["D", op, kind, window, sym, syms != null ? syms.copy() : []];
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
			case BFeature(src): ["F", src]; // opaque leaf keyed by verbatim source
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
			case SProj(_, _): 1;
			case SPanel(_, _, _, _): 1;
		};
	}

	static function countScalar(n:ScalarNode):Int {
		return switch (n) {
			case KConst(_) | KParam(_): 1;
			case KFeature(_): 1;
			case KSeries(s): countSeries(s);
			case KLookback(s, _): 1 + countSeries(s);
			case KNp(_, a, _, b):
				1 + countSeries(a) + (b != null ? countSeries(b) : 0);
			case KPd(_, _, _, _, _): 1;
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
			case BFeature(_): 1; // opaque leaf: one atomic node
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
	 *
	 * Memoized on `g.shapeVectorCache` the same way `structuralKey`/`nodeCount` are: elites
	 * surviving across generations stop re-walking the tree every speciation pass.
	 */
	public static function shapeVector(g:StrategyGenome):haxe.ds.Vector<Int> {
		var cached = g.shapeVectorCache;
		if (cached != null) return cached;
		var v = new haxe.ds.Vector<Int>(SHAPE_KINDS.length);
		for (i in 0...v.length) v[i] = 0;
		inline function bump(i:Int):Void v[i] = v[i] + 1;
		function walkSeries(n:SeriesNode):Void {
			switch (n) {
				case SPrice(_): bump(K_SPRICE);
				case SInd(_, _, _, src): bump(K_SIND); if (src != null) walkSeries(src);
				case SProj(_, _): bump(K_SPROJ);
				case SPanel(_, _, _, _): bump(K_SPANEL);
			}
		}
		function walkScalar(n:ScalarNode):Void {
			switch (n) {
				case KConst(_): bump(K_KCONST);
				case KParam(_): bump(K_KPARAM);
				case KFeature(_): bump(K_KFEATURE);
				case KSeries(s): bump(K_KSERIES); walkSeries(s);
				case KLookback(s, _): bump(K_KLOOKBACK); walkSeries(s);
				case KNp(_, a, _, b):
					bump(K_KNP);
					walkSeries(a);
					if (b != null) walkSeries(b);
				case KPd(_, _, _, _, _): bump(K_KPD);
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
				case BFeature(_): bump(K_BFEATURE);
			}
		}
		walkBool(g.entryLong);
		walkBool(g.entryShort);
		walkBool(g.exitLong);
		walkBool(g.exitShort);
		walkScalar(g.size);
		g.shapeVectorCache = v;
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
		"KConst", "KParam", "KArith", "KSeries", "KLookback", "KFeature", "KHole", "SPrice", "SInd", "SProj",
		"BFeature", "SPanel", "KNp", "KPd"];

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
	static inline var K_SPROJ = 16;
	static inline var K_BFEATURE = 17; // before SPanel so existing shapeVector indices stay stable
	static inline var K_SPANEL = 18;
	static inline var K_KNP = 19; // append only — prior indices stable
	static inline var K_KPD = 20;

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