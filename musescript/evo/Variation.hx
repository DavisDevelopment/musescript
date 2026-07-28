package musescript.evo;

import musescript.evo.TreeSurgery;
import musescript.evo.Fitness;

/**
 * Typed GP variation operators — closed under MuseGene types (no repair pass ever needed, same
 * discipline as musegene/variation.py). Ports Python's point_mutate/subtree_crossover/
 * promote_param/compact_params using TreeSurgery's path-based node addressing instead of
 * Python's object-identity approach (see TreeSurgery.hx's doc comment for why).
 *
 * A genome is 5 "slots": entryLong/entryShort/exitLong/exitShort (BoolNode roots) and size
 * (a ScalarNode root). `buildCatalog` walks all 5, tagging every reachable Bool/Scalar/Series
 * position with (slot, kind, path) — point_mutate and promote_param both pick from this same
 * catalog, just filtered differently.
 *
 * `EKind` / `CatalogEntry` / `CatalogSite` live in their own modules so NMA attribution can
 * import sites without a Variation↔NMA cycle.
 */

/** Lightweight int->int mapping via two parallel arrays, replacing `Map<Int,Int>` for the
 * small param-index remappings this file builds (`remapOffsets`/`compactParams`). Confirmed via
 * `std/jvm/_std/haxe/ds/IntMap.hx`: `Map<Int,V>` on the JVM target is a thin wrapper over
 * `java.util.HashMap<Integer,V>`, so every `set`/`get`/`exists` call boxes the key through
 * `java.lang.Integer` -- real cost on `compactParams`, which runs on every mutation/crossover
 * child. Every mapping built here is small (bounded by a genome's/donor's param count,
 * typically well under a few dozen), where a linear scan over unboxed ints is allocation-free
 * and, at this size, no slower than a hash lookup that has to box first. */
class ParamMapping {
	var keys:Array<Int> = [];
	var values:Array<Int> = [];

	public function new() {}

	public function set(key:Int, value:Int):Void {
		keys.push(key);
		values.push(value);
	}

	/** Returns the mapped value, or `key` unchanged if unmapped -- folds every existing call
	 * site's `mapping.exists(i) ? mapping.get(i) : i` idiom into one call. */
	public function get(key:Int):Int {
		for (i in 0...keys.length) if (keys[i] == key) return values[i];
		return key;
	}
}

class Variation {
	var rng:Rand;
	/**
	 * Indicator name pool `growSeries` draws from. Defaults to `Palette.INDS` (the closed
	 * 12-name set mirrored from musegene/palette.py) so EXISTING callers/persisted genomes
	 * see zero behavior change. Pass `RegistryPalette.compatibleNames()` for the wide,
	 * zero-maintenance vocabulary covering every ported `ta` indicator that fits SInd's
	 * shape -- see RegistryPalette's doc comment.
	 */
	var indicatorPool:Array<String>;
	/** Adaptive node-type-choice weights (see GrowthWeights.hx). Defaults to a fresh instance
	 * seeded with this file's ORIGINAL literal probabilities, so a caller that never wires a
	 * shared tuner (or never triggers its reward loop) sees zero behavior change from before this
	 * existed. `attributedPointMutate` is the one path that actually calls `tuner.reward(...)` --
	 * see its doc comment. */
	public var tuner:GrowthWeights;

	/**
	 * Per-generation memo of parent `siteDeltas` (PLAN_EVO_SPEED P1.1). Tournament re-picks the
	 * same elites many times per gen; ablation profiles are deterministic for a fixed oracle —
	 * recomputing them per child is pure waste once P0 caches make each eval cheap.
	 */
	var siteDeltaMemo:Map<String, {baseline:Float, deltas:Array<Float>, keys:IntPairList}> = new Map();
	/** Test/telemetry: times `computeSiteDeltas` returned a same-gen memo hit. */
	public var siteDeltaMemoHits:Int = 0;
	/**
	 * Per-generation memo of donor-splice oracle scores, keyed by the digest of
	 * `(parentKey, slot, path, donorBoolLanes)`. Tournament + Fisher–Yates re-samples the same
	 * (parent, site, donor) triples often enough that cold donor evals otherwise dominate
	 * `step.xo` under nested AttrPool workers.
	 *
	 * The key used to be that tuple spelled out as a `String`. At pop=1000 the concatenation and
	 * its `HashMap` nodes were among the largest allocators on the eval barrier, so the tuple is
	 * hashed instead and the memo keyed on the lanes (JIT guide §3.3).
	 */
	var donorScoreMemo:IntPairMap<Float> = new IntPairMap();
	public var donorScoreMemoHits:Int = 0;
	/** Same-gen bool-site catalogs / donor pools keyed by structural key (elites are re-picked). */
	var boolCatalogMemo:Map<String, Array<CatalogEntry>> = new Map();
	/**
	 * Full `buildCatalog` memo (bool+scalar+series). Blind mutate/XO re-pick elites constantly;
	 * without this the same parent paid a fresh TreeSurgery walk per child (measured: attr-cross
	 * 0 still left ~42 ms CPU in `step.xo` — mostly catalog/donor walks, not the oracle).
	 */
	var fullCatalogMemo:Map<String, Array<CatalogEntry>> = new Map();
	var donorPoolMemo:Map<String, Array<Dynamic>> = new Map();
	/**
	 * Shared across `forkForSlot` workers so a parent ablated on one child slot is warm for every
	 * other slot that tournament-picks the same elite. Guarded: parallel step writes the memo.
	 */
	var memoLock = new EvoLock();
	var indicatorPoolRef:Array<String>;
	var baseSeed:Int;
	/**
	 * Bumped every `beginGeneration`. Instance catalogs on `StrategyGenome` compare against this
	 * instead of being eagerly cleared (elites survive across gens as the same objects).
	 */
	var cacheGen:Int = 0;

	public function new(seed:Int, ?indicatorPool:Array<String>, ?tuner:GrowthWeights) {
		rng = new Rand(seed);
		this.baseSeed = seed;
		this.indicatorPool = indicatorPool != null ? indicatorPool : Palette.INDS;
		this.indicatorPoolRef = this.indicatorPool;
		this.tuner = tuner != null ? tuner : new GrowthWeights();
	}

	/**
	 * Per-slot Variation for parallel child production: own RNG stream, shared tuner + site-delta
	 * memo. Selection/crossover/mutate choice stays on EvolutionEngine's streams; only the
	 * Variation-internal draws (site picks, growBool, donor sample) move to
	 * `seed + VARIATION_PARALLEL + slot * 100003`.
	 */
	public function forkForSlot(slot:Int):Variation {
		var v = new Variation(baseSeed + RngStreams.VARIATION_PARALLEL + slot * 100003, indicatorPoolRef, tuner);
		v.siteDeltaMemo = siteDeltaMemo;
		v.donorScoreMemo = donorScoreMemo;
		v.boolCatalogMemo = boolCatalogMemo;
		v.fullCatalogMemo = fullCatalogMemo;
		v.donorPoolMemo = donorPoolMemo;
		v.memoLock = memoLock;
		v.cacheGen = cacheGen;
		return v;
	}

	/**
	 * Per-deme Variation for archipelago Phase B: own RNG + own memo maps (no shared `memoLock`).
	 * Deme workers run under AttrPool nesting, so children stay serial inside the island — the
	 * parallelism is across demes, not inside them.
	 */
	public function forkDeme(deme:Int):Variation {
		var v = new Variation(baseSeed + RngStreams.VARIATION_PARALLEL + 900000 + deme * 100003, indicatorPoolRef, tuner);
		v.cacheGen = cacheGen;
		return v;
	}

	/** Clear per-parent ablation / donor-score memos — call once at the start of each `EvolutionEngine.step`. */
	public function beginGeneration():Void {
		cacheGen++;
		memoLock.acquire();
		siteDeltaMemo = new Map();
		siteDeltaMemoHits = 0;
		donorScoreMemo = new IntPairMap();
		donorScoreMemoHits = 0;
		boolCatalogMemo = new Map();
		fullCatalogMemo = new Map();
		donorPoolMemo = new Map();
		memoLock.release();
	}

	// ---- growth (unchanged shape, BNot/BTrend added to close the reachability gap found
	// while surveying evolution-system coverage: both were typed but never generated) ----

	function growSeries(depth:Int):SeriesNode {
		if (depth <= 0 || rng.float() < 0.4)
			return SPrice(rng.pick(Palette.FIELDS));
		return SInd(rng.pick(indicatorPool), rng.pick(Palette.FIELDS), rng.pick(Palette.WINDOWS), null);
	}

	/**
	 * `tagOut`, when supplied, records EVERY category:tag choice made by this call AND every
	 * recursive sub-call it makes (e.g. a single growBool call can push `["boolTerm:cmp",
	 * "scalarTerm:multiOutput", "multiOutput:macd"]` if it happens to grow a comparison against a
	 * macd field) -- a whole-subtree trajectory, not just the outermost pick. This used to be
	 * outermost-only, which silently meant `riskExit`/`multiOutput`/`scalarTerm`/`scalarRecurse`
	 * could NEVER be rewarded at all: `attributedPointMutate` only ever calls `growBool` directly,
	 * so any tag chosen by a NESTED growScalar/growRiskExit/growMultiOutputField call (which is
	 * every single one of those four categories' only reachable call sites) was silently dropped.
	 * Confirmed empirically: an 80-generation real run showed `boolTerm`/`boolRecurse` clearly
	 * converging (cross fell from the highest-weighted tag to the lowest; `or` rose to 62%) while
	 * the other four categories sat at their exact seeded defaults to the decimal, unmoved. Now
	 * every nested growth call threads `tagOut` through, so the whole trajectory that produced a
	 * mutation's replacement subtree gets credited, not just its outermost shape.
	 */
	function growScalar(depth:Int, ?pool:Array<EvoParam>, ?tagOut:Array<String>):ScalarNode {
		if (depth <= 0 || rng.float() < 0.5) {
			var choice = tuner.pick("scalarTerm", rng);
			if (choice == "param" && pool == null) choice = "series"; // no pool to mint from -- fall back
			if (tagOut != null) tagOut.push('scalarTerm:$choice');
			return switch (choice) {
				case "param": mintParam(pool);
				case "multiOutput": growMultiOutputField(tagOut);
				default: KSeries(growSeries(0));
			};
		}
		var choice = tuner.pick("scalarRecurse", rng);
		if (choice == "param" && pool == null) choice = "series"; // no pool to mint from -- fall back
		if (tagOut != null) tagOut.push('scalarRecurse:$choice');
		return switch (choice) {
			case "series": KSeries(growSeries(0));
			case "param": mintParam(pool);
			case "const": KConst(rng.float() * 4 - 2);
			default: KArith(rng.pick(Palette.ARITH), growScalar(depth - 1, pool, tagOut), growScalar(depth - 1, pool, tagOut));
		};
	}

	/**
	 * Multi-output indicator field access: macd(...).hist, bbands(...).upper/mid/lower,
	 * stoch(...).k/d -- indicators whose (series,window)->scalar shape `SInd` can't represent
	 * (they return a NAMED-FIELD object, see BuiltinSigs.hx's TObject signatures for macd/bbands/
	 * stoch), so RegistryPalette's indicator pool excludes them entirely (see its own doc comment:
	 * "Multi-output ... returns ... are excluded too -- covering those needs a richer node shape
	 * than SInd, not a bigger name list"). This IS that richer shape, arrived at the same way
	 * growRiskExit was: a `KFeature` bare-expression leaf (already a valid, already-generically-
	 * handled ScalarNode terminal everywhere -- Canonical/TreeSurgery/Expand needed zero new
	 * match arms) rather than a new node variant. `promoteParam` doesn't reach INTO these window/
	 * arg literals (they're baked into the expression string, not a `KConst` sub-node) -- accepted
	 * as a v1 limit; variety comes from drawing a fresh combo per growth call, not from mutation
	 * fine-tuning an existing one's window in place.
	 *
	 * No native WASM lowering exists for macd/bbands/stoch (StrategyWasmEmitter has no case for
	 * them), so a genome using this terminal always takes CorpusEvoRun's JS-fallback path --
	 * correct, just not WASM-accelerated, the same honest tradeoff every other indicator beyond
	 * the native dozen already has.
	 */
	function growMultiOutputField(?tagOut:Array<String>):ScalarNode {
		var choice = tuner.pick("multiOutput", rng);
		if (tagOut != null) tagOut.push('multiOutput:$choice');
		return switch (choice) {
			case "macd":
				var combo = rng.pick([[12, 26, 9], [5, 13, 5], [8, 21, 9], [3, 10, 16]]);
				var field = rng.pick(["macd", "signal", "hist"]);
				KFeature('macd("close", ${combo[0]}, ${combo[1]}, ${combo[2]}).$field');
			case "bbands":
				var w = rng.pick(Palette.WINDOWS);
				var mult = rng.pick([1.5, 2.0, 2.5, 3.0]);
				var field = rng.pick(["upper", "mid", "lower"]);
				KFeature('bbands("close", $w, $mult).$field');
			default:
				var combo = rng.pick([[14, 3, 3], [5, 3, 3], [21, 5, 5]]);
				var field = rng.pick(["k", "d"]);
				KFeature('stoch(${combo[0]}, ${combo[1]}, ${combo[2]}).$field');
		};
	}

	/** `growBool`'s terminal case now includes `BTrend` alongside `BCross`/`BCmp`, and the
	 * recursive case can produce `BNot` — both existed in the type system but were previously
	 * structurally unreachable (found while surveying evolution-system coverage against the
	 * full stdlib). A further terminal, `growRiskExit`, gives evolution direct access to
	 * risk-managed exits (stop-loss/take-profit/time-stop) instead of only ever discovering
	 * signal-reversal exits — see growRiskExit's own doc comment. */
	/** `tagOut`: see growScalar's doc comment -- captures the WHOLE trajectory (this call's own
	 * pick plus every nested growScalar/growRiskExit/growMultiOutputField/growBool sub-call's). */
	function growBool(depth:Int, ?pool:Array<EvoParam>, ?tagOut:Array<String>):BoolNode {
		if (depth <= 0 || rng.float() < 0.45) {
			// Learned library (opt-in via --learn-library): small reach into BHole(motif).
			// Drawn BEFORE boolTerm so seeded defaults stay bit-identical when library is empty.
			if (LearnedLibrary.size() > 0 && tuner.hasCategory("boolLibrary") && rng.float() < 0.18) {
				var libTag = tuner.pick("boolLibrary", rng);
				var motif = LearnedLibrary.get(libTag);
				if (motif != null) {
					if (tagOut != null) tagOut.push('boolLibrary:$libTag');
					return BHole(LearnedLibrary.cloneBool(motif));
				}
			}
			var choice = tuner.pick("boolTerm", rng);
			if (tagOut != null) tagOut.push('boolTerm:$choice');
			return switch (choice) {
				case "cross": BCross(rng.pick(Palette.CROSS), growSeries(1), growSeries(1));
				case "cmp": BCmp(rng.pick(Palette.CMP), growScalar(1, pool, tagOut), growScalar(1, pool, tagOut));
				case "trend": BTrend(rng.pick(Palette.CROSS), growSeries(1), rng.pick(Palette.WINDOWS));
				default: growRiskExit(tagOut);
			};
		}
		var choice = tuner.pick("boolRecurse", rng);
		if (tagOut != null) tagOut.push('boolRecurse:$choice');
		return switch (choice) {
			case "and": BAnd(growBool(depth - 1, pool, tagOut), growBool(depth - 1, pool, tagOut));
			case "or": BOr(growBool(depth - 1, pool, tagOut), growBool(depth - 1, pool, tagOut));
			default: BNot(growBool(depth - 1, pool, tagOut));
		};
	}

	/**
	 * Risk-managed exit terminals: stop-loss, take-profit, and a time-stop, built from
	 * `unrealized_pnl_pct()`/`bars_in_trade()` (see TradeBuiltins.hx's registration and
	 * StrategyWasmEmitter's native lowering) via the ALREADY-generic `BCmp` comparator — no new
	 * BoolNode variant needed, these are just KFeature leaves with a bare-expression body (the
	 * same convention `KFeature` was designed for, see ScalarNode.hx/Expand.hx). `unrealized_pnl_
	 * pct()` is direction-normalized (favorable/unfavorable regardless of long or short), so a
	 * single condition works whether it ends up composed into exitLong or exitShort.
	 *
	 * This closes a real gap: every corpus/evolved champion up to this point was a bare
	 * crossover-reversal strategy with NO risk management at all (see CorpusEvoRun's OOS re-score
	 * discipline flagging "did not hold" cases) — reachable ONLY via signal-reversal exits before
	 * this, because growBool had no other terminal shape. `promoteParam` already generically
	 * promotes any `KConst` leaf to a tunable `@param`, so these thresholds get free access to
	 * the SAME tuning machinery scalar constants elsewhere in the genome already have — no new
	 * promotion logic needed either.
	 */
	function growRiskExit(?tagOut:Array<String>):BoolNode {
		var choice = tuner.pick("riskExit", rng);
		if (tagOut != null) tagOut.push('riskExit:$choice');
		return switch (choice) {
			case "stopLoss":
				// Unrealized loss past `pct` (1%-15%) closes the position.
				var pct = Math.round((rng.float() * 0.14 + 0.01) * 1000) / 1000;
				BCmp("<", KFeature("unrealized_pnl_pct()"), KConst(-pct));
			case "takeProfit":
				// Unrealized gain past `pct` (1%-20%) closes the position.
				var pct = Math.round((rng.float() * 0.19 + 0.01) * 1000) / 1000;
				BCmp(">", KFeature("unrealized_pnl_pct()"), KConst(pct));
			default:
				// Time-stop: close after holding for more than N bars (3-60).
				var n = Math.round(rng.float() * 57) + 3;
				BCmp(">", KFeature("bars_in_trade()"), KConst(n));
		};
	}

	function mintParam(pool:Array<EvoParam>):ScalarNode {
		var idx = pool.length;
		pool.push({ name: 'p$idx', defaultValue: Math.round((rng.float() * 100) * 1000) / 1000,
			min: 0.0, max: 100.0, step: 0.5, tune: "grid" });
		return KParam(idx);
	}

	/** `size` now grows a real scalar tree (with param minting) instead of a hardcoded
	 * `KConst(1)` — the second reachability gap found while surveying evolution-system
	 * coverage: the type system always supported an evolved size expression, the generator
	 * just never used it. */
	public function randomGenome(depth:Int = 3):StrategyGenome {
		var pool:Array<EvoParam> = [];
		var g:StrategyGenome = {
			entryLong: growBool(depth, pool),
			entryShort: growBool(depth, pool),
			exitLong: growBool(depth, pool),
			exitShort: growBool(depth, pool),
			size: growScalar(1, pool),
			params: pool,
			name: "musegene",
			lineage: [],
			seedOrigin: rng.seed
		};
		return compactParams(g);
	}

	// ---- catalog: every Bool/Scalar/Series position across all 5 slots, path-tagged ----

	/**
	 * True iff `g` contains a `BHole`/`KHole` ANYWHERE across its 5 slots -- the single switch
	 * `buildCatalog` uses to decide whether to hand back every node (today's behavior, unchanged
	 * for every genome random growth/crossover/corpus-seeding without `evolve(...)` markers ever
	 * produces) or only nodes reachable from inside a hole boundary (see CorpusSeed's `evolve(...)`
	 * recognition, which is the only thing that ever constructs a `BHole`/`KHole`). This is what
	 * makes hole-restricted evolution strictly OPT-IN: a genome with zero holes anywhere is
	 * mutated/crossed-over exactly as it always has been.
	 */
	public static function isTemplated(g:StrategyGenome):Bool {
		return boolHasHole(g.entryLong) || boolHasHole(g.entryShort)
			|| boolHasHole(g.exitLong) || boolHasHole(g.exitShort) || scalarHasHole(g.size);
	}

	static function boolHasHole(n:BoolNode):Bool {
		return switch (n) {
			case BHole(_): true;
			case BAnd(a, b) | BOr(a, b): boolHasHole(a) || boolHasHole(b);
			case BNot(a): boolHasHole(a);
			case BCmp(_, a, b): scalarHasHole(a) || scalarHasHole(b);
			case BCross(_, _, _) | BTrend(_, _, _): false;
		};
	}

	static function scalarHasHole(n:ScalarNode):Bool {
		return switch (n) {
			case KHole(_): true;
			case KArith(_, a, b): scalarHasHole(a) || scalarHasHole(b);
			case KConst(_) | KParam(_) | KFeature(_) | KSeries(_) | KLookback(_, _): false;
		};
	}

	function buildCatalog(g:StrategyGenome):Array<CatalogEntry> {
		// Instance hit first: same elite object, no lock. Map hit second: same structure, other ref.
		if (g.variationCacheGen == cacheGen && g.catalogCache != null) return g.catalogCache;
		// `armed = !templated`: an untemplated genome starts (and stays) fully recordable, byte-
		// identical to this function's behavior before holes existed. A templated genome starts
		// UNrecordable and only becomes recordable once TreeSurgery's collect* walk crosses an
		// actual BHole/KHole boundary -- see TreeSurgery.collectBool's doc comment.
		var key = Canonical.structuralKey(g);
		memoLock.acquire();
		var hit = fullCatalogMemo.get(key);
		if (hit != null) {
			memoLock.release();
			g.catalogCache = hit;
			g.variationCacheGen = cacheGen;
			return hit;
		}
		memoLock.release();
		var armed = !isTemplated(g);
		var out:Array<CatalogEntry> = [];
		addBoolSlot(out, armed, 0, g.entryLong);
		addBoolSlot(out, armed, 1, g.entryShort);
		addBoolSlot(out, armed, 2, g.exitLong);
		addBoolSlot(out, armed, 3, g.exitShort);
		var sc2:Array<{path:GPath, node:ScalarNode}> = [];
		TreeSurgery.collectScalar(g.size, [], sc2, armed);
		for (e in sc2) out.push({ slot: 4, kind: EScalar, path: e.path });
		var xc2:Array<{path:GPath, node:SeriesNode}> = [];
		TreeSurgery.collectSeriesInScalar(g.size, [], xc2, armed);
		for (e in xc2) out.push({ slot: 4, kind: ESeries, path: e.path });
		memoLock.acquire();
		if (!fullCatalogMemo.exists(key)) fullCatalogMemo.set(key, out);
		memoLock.release();
		g.catalogCache = out;
		g.variationCacheGen = cacheGen;
		return out;
	}

	/**
	 * Bool sites only — attributed mutate/XO never consult Scalar/Series catalogs. Skipping
	 * those walks cuts a large fraction of `buildCatalog` work on every attributed child.
	 * Memoized by structural key within a generation (elites are tournament-re-picked).
	 */
	function buildBoolCatalog(g:StrategyGenome):Array<CatalogEntry> {
		if (g.variationCacheGen == cacheGen && g.boolCatalogCache != null) return g.boolCatalogCache;
		var key = Canonical.structuralKey(g);
		memoLock.acquire();
		var hit = boolCatalogMemo.get(key);
		if (hit != null) {
			memoLock.release();
			g.boolCatalogCache = hit;
			g.variationCacheGen = cacheGen;
			return hit;
		}
		memoLock.release();
		var armed = !isTemplated(g);
		var out:Array<CatalogEntry> = [];
		addBoolSitesOnly(out, armed, 0, g.entryLong);
		addBoolSitesOnly(out, armed, 1, g.entryShort);
		addBoolSitesOnly(out, armed, 2, g.exitLong);
		addBoolSitesOnly(out, armed, 3, g.exitShort);
		memoLock.acquire();
		if (!boolCatalogMemo.exists(key)) boolCatalogMemo.set(key, out);
		memoLock.release();
		g.boolCatalogCache = out;
		g.boolSiteKeysCache = siteKeysFresh(g, out);
		g.variationCacheGen = cacheGen;
		return out;
	}

	/** Pulled out of `buildCatalog` as a real method (was a local closure allocated fresh on
	 * every call) -- `buildCatalog` runs on every mutation/crossover child, hundreds of times
	 * per generation, so a per-call closure object was avoidable allocation pressure. */
	function addBoolSlot(out:Array<CatalogEntry>, armed:Bool, slot:Int, root:BoolNode):Void {
		var bc:Array<{path:GPath, node:BoolNode}> = [];
		TreeSurgery.collectBool(root, [], bc, armed);
		for (e in bc) out.push({ slot: slot, kind: EBool, path: e.path });
		var sc:Array<{path:GPath, node:ScalarNode}> = [];
		TreeSurgery.collectScalarInBool(root, [], sc, armed);
		for (e in sc) out.push({ slot: slot, kind: EScalar, path: e.path });
		var xc:Array<{path:GPath, node:SeriesNode}> = [];
		TreeSurgery.collectSeriesInBool(root, [], xc, armed);
		for (e in xc) out.push({ slot: slot, kind: ESeries, path: e.path });
	}

	function addBoolSitesOnly(out:Array<CatalogEntry>, armed:Bool, slot:Int, root:BoolNode):Void {
		var bc:Array<{path:GPath, node:BoolNode}> = [];
		TreeSurgery.collectBool(root, [], bc, armed);
		for (e in bc) out.push({ slot: slot, kind: EBool, path: e.path });
	}

	function withBoolRepl(g:StrategyGenome, entry:CatalogEntry, repl:BoolNode):StrategyGenome {
		var out = copyGenome(g);
		var v = switch (entry.slot) {
			case 0: TreeSurgery.replaceBoolWithBool(g.entryLong, entry.path, repl);
			case 1: TreeSurgery.replaceBoolWithBool(g.entryShort, entry.path, repl);
			case 2: TreeSurgery.replaceBoolWithBool(g.exitLong, entry.path, repl);
			case 3: TreeSurgery.replaceBoolWithBool(g.exitShort, entry.path, repl);
			default: throw "withBoolRepl: size slot can't hold a BoolNode";
		};
		return switch (entry.slot) {
			case 0: setEntryLong(out, v);
			case 1: setEntryShort(out, v);
			case 2: setExitLong(out, v);
			case 3: setExitShort(out, v);
			default: out;
		};
	}

	function withScalarRepl(g:StrategyGenome, entry:CatalogEntry, repl:ScalarNode):StrategyGenome {
		return switch (entry.slot) {
			case 0: setEntryLong(g, TreeSurgery.replaceBoolWithScalar(g.entryLong, entry.path, repl));
			case 1: setEntryShort(g, TreeSurgery.replaceBoolWithScalar(g.entryShort, entry.path, repl));
			case 2: setExitLong(g, TreeSurgery.replaceBoolWithScalar(g.exitLong, entry.path, repl));
			case 3: setExitShort(g, TreeSurgery.replaceBoolWithScalar(g.exitShort, entry.path, repl));
			case 4: setSize(g, TreeSurgery.replaceScalarWithScalar(g.size, entry.path, repl));
			default: g;
		};
	}

	function withSeriesRepl(g:StrategyGenome, entry:CatalogEntry, repl:SeriesNode):StrategyGenome {
		return switch (entry.slot) {
			case 0: setEntryLong(g, TreeSurgery.replaceBoolWithSeries(g.entryLong, entry.path, repl));
			case 1: setEntryShort(g, TreeSurgery.replaceBoolWithSeries(g.entryShort, entry.path, repl));
			case 2: setExitLong(g, TreeSurgery.replaceBoolWithSeries(g.exitLong, entry.path, repl));
			case 3: setExitShort(g, TreeSurgery.replaceBoolWithSeries(g.exitShort, entry.path, repl));
			case 4: setSize(g, TreeSurgery.replaceSeriesInScalarWithSeries(g.size, entry.path, repl));
			default: g;
		};
	}

	static function copyGenome(g:StrategyGenome):StrategyGenome {
		return { entryLong: g.entryLong, entryShort: g.entryShort, exitLong: g.exitLong,
			exitShort: g.exitShort, size: g.size, params: g.params.copy(), name: g.name,
			lineage: g.lineage != null ? g.lineage.copy() : [], seedOrigin: g.seedOrigin,
			// Projections are genome identity, not a cache — preserve across splices. Deep-copy
			// decls so φ-delta map mutations cannot leak into the parent.
			projections: g.projections != null ? [for (p in g.projections) copyProj(p)] : null };
	}

	static function setEntryLong(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.entryLong = v; return o; }
	static function setEntryShort(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.entryShort = v; return o; }
	static function setExitLong(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.exitLong = v; return o; }
	static function setExitShort(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.exitShort = v; return o; }
	static function setSize(g:StrategyGenome, v:ScalarNode):StrategyGenome { var o = copyGenome(g); o.size = v; return o; }

	// ---- operators ----

	/**
	 * Mirror of `EvolutionEngine.maxNodes` for grow depth throttling in blind mutate.
	 * Near/over the budget, depth collapses to terminals so we don't AND/OR-explode into a
	 * child that `produceChild` would just discard.
	 */
	public static var maxNodes:Int = 40;

	/** Replace one random subtree (any slot, any depth) with a fresh same-typed subtree —
	 * musegene/variation.py's `point_mutate`, ported via TreeSurgery paths instead of Python's
	 * identity-based node replacement. */
	public function pointMutate(g:StrategyGenome, maxDepth:Int = 2):StrategyGenome {
		var catalog = buildCatalog(g);
		if (catalog.length == 0) return g;
		var entry = catalog[rng.int(catalog.length)];
		var dCap = maxDepth;
		var budget = maxNodes;
		if (budget > 0) {
			var n = Canonical.nodeCount(g);
			if (n >= budget) dCap = 0;
			else if (n >= budget - 8) dCap = maxDepth < 1 ? maxDepth : 1;
		}
		var d = rng.int(dCap + 1);
		var boolRepl:Null<BoolNode> = null;
		var mutated = switch (entry.kind) {
			case EBool:
				boolRepl = growBool(d);
				withBoolRepl(g, entry, boolRepl);
			case EScalar: withScalarRepl(g, entry, growScalar(d));
			case ESeries: withSeriesRepl(g, entry, growSeries(d));
		};
		mutated.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		var out = compactParams(mutated);
		if (boolRepl != null) maybeRegisterDirtySpineBool(g, entry, boolRepl, out);
		return out;
	}

	/** Swap a random same-typed subtree from `g2` into `g1` (child inherits g1's frame) —
	 * musegene/variation.py's `subtree_crossover`. Donor `KParam` references get remapped into
	 * g1's param space (new specs appended, copied from g2's), matching Python's
	 * `_import_params`. */
	public function subtreeCrossover(g1:StrategyGenome, g2:StrategyGenome):StrategyGenome {
		var catalog1 = buildCatalog(g1);
		if (catalog1.length == 0) return g1;
		var site = catalog1[rng.int(catalog1.length)];

		var donorPool = donorsOfKind(g2, site.kind);
		if (donorPool.length == 0) return g1;
		var donorIdx = rng.int(donorPool.length);

		var extraParams:Array<EvoParam> = [];
		var offset = g1.params.length;
		var result:StrategyGenome = switch (site.kind) {
			case EBool:
				var donor:BoolNode = cast donorPool[donorIdx];
				var refs = [];
				paramRefsInBool(donor, refs);
				var mapping = remapOffsets(refs, offset, extraParams, g2.params);
				var remapped = remapBool(donor, mapping);
				var child = withBoolRepl(g1, site, remapped);
				child.params = g1.params.concat(extraParams);
				child.lineage = [Canonical.structuralKey(g1), Canonical.structuralKey(g2)];
				var out = compactParams(child);
				maybeRegisterDirtySpineBool(g1, site, remapped, out);
				return out;
			case EScalar:
				var donor:ScalarNode = cast donorPool[donorIdx];
				var refs = [];
				paramRefsInScalar(donor, refs);
				var mapping = remapOffsets(refs, offset, extraParams, g2.params);
				withScalarRepl(g1, site, remapScalar(donor, mapping));
			case ESeries:
				var donor:SeriesNode = cast donorPool[donorIdx];
				withSeriesRepl(g1, site, donor); // SeriesNode never contains a ScalarNode -> no param refs possible
		};
		result.params = g1.params.concat(extraParams);
		result.lineage = [Canonical.structuralKey(g1), Canonical.structuralKey(g2)];
		return compactParams(result);
	}

	/**
	 * Attribution-guided crossover -- the same ablation-based profit-contribution idea
	 * `attributedPointMutate` uses for mutation, extended to BOTH sides of a crossover:
	 *
	 *  - RECIPIENT site (in `g1`): ablate each BoolNode position to an always-true tautology and
	 *    measure `baseline - ablated`, exactly like attributedPointMutate. A low/negative delta
	 *    means that node isn't pulling weight -- SAFE to overwrite. Rank-weighted pick biased
	 *    toward the least important site, so crossover doesn't gamble away a genome's one real
	 *    working signal.
	 *
	 *  - DONOR subtree (from `g2`): instead of a blind random pick from every same-typed subtree
	 *    in `g2`, sample up to `donorSampleCap` candidates and measure what EACH would actually do
	 *    if spliced into `g1` at the chosen site (`evalFn` on the spliced genome directly -- this
	 *    is compatibility with g1, not the donor's standalone importance inside g2, which could be
	 *    a totally different context). Rank-weighted pick biased toward the HIGHEST resulting
	 *    fitness. Capped rather than exhaustive: g2 can have many BoolNode subtrees across its 4
	 *    slots, and each donor candidate costs one full evalFn call -- same cost-consciousness that
	 *    motivated this session's fitness cache and prefix triage.
	 *
	 * Bool-only, matching `attributedPointMutate`'s exact scoping rationale (that's where real
	 * trading DECISIONS live, and it keeps the extra eval cost bounded and comparable). Falls back
	 * to the plain uniform `subtreeCrossover` when g1 has no BoolNode sites, or with a small fixed
	 * probability regardless -- same explore-preserving discipline as attributedPointMutate's own
	 * 20% fallback, so crossover doesn't become entirely exploitation-driven either.
	 */
	public function attributedSubtreeCrossover(g1:StrategyGenome, g2:StrategyGenome, evalFn:StrategyGenome->Float, donorSampleCap:Int = 2):StrategyGenome {
		var boolSites = buildBoolCatalog(g1);
		if (boolSites.length == 0 || rng.float() < 0.2) return subtreeCrossover(g1, g2);

		var pack = computeSiteDeltas(g1, boolSites, evalFn);
		var siteDeltas = pack.deltas;
		// Credit-cuts bank-only packs already put means in `deltas` (baseline NaN). Re-adding
		// priors doubles every weight uniformly — ranking-identical and a wasted lock+alloc.
		var siteImportance:Array<Float>;
		if (Math.isNaN(pack.baseline)) {
			siteImportance = siteDeltas;
		} else {
			var sitePriors = musescript.evo.nma.NmaCreditBank.meansPairs(pack.keys);
			siteImportance = [for (i in 0...boolSites.length) siteDeltas[i] + sitePriors[i]];
		}
		var siteOrder = [for (i in 0...boolSites.length) i];
		siteOrder.sort((a, b) -> siteImportance[a] < siteImportance[b] ? -1 : siteImportance[a] > siteImportance[b] ? 1 : 0);
		var siteWeights = [for (_ in 0...boolSites.length) 1.0];
		for (rank in 0...siteOrder.length) siteWeights[siteOrder[rank]] = siteOrder.length - rank; // least important -> highest weight
		var site = boolSites[weightedPickIndex(siteWeights)];

		var fullDonorPool = donorsOfKind(g2, EBool);
		if (fullDonorPool.length == 0) return subtreeCrossover(g1, g2);
		var sampled:Array<BoolNode> = [];
		if (fullDonorPool.length <= donorSampleCap) {
			sampled = cast fullDonorPool.copy();
		} else {
			var idxs = [for (i in 0...fullDonorPool.length) i];
			for (i in 0...idxs.length - 1) { // Fisher-Yates, take the first donorSampleCap
				var j = i + rng.int(idxs.length - i);
				var t = idxs[i]; idxs[i] = idxs[j]; idxs[j] = t;
			}
			for (i in 0...donorSampleCap) sampled.push(cast fullDonorPool[idxs[i]]);
		}
		var donorScores = scoreDonors(g1, site, sampled, evalFn);
		var donorOrder = [for (i in 0...sampled.length) i];
		donorOrder.sort((a, b) -> donorScores[a] < donorScores[b] ? -1 : donorScores[a] > donorScores[b] ? 1 : 0);
		var donorWeights = [for (_ in 0...sampled.length) 1.0];
		for (rank in 0...donorOrder.length) donorWeights[donorOrder[rank]] = rank + 1; // rank 0 (worst) -> weight 1, best -> highest
		var donor = sampled[weightedPickIndex(donorWeights)];

		var extraParams:Array<EvoParam> = [];
		var offset = g1.params.length;
		var refs = [];
		paramRefsInBool(donor, refs);
		var mapping = remapOffsets(refs, offset, extraParams, g2.params);
		var remapped = remapBool(donor, mapping);
		var result = withBoolRepl(g1, site, remapped);
		result.params = g1.params.concat(extraParams);
		result.lineage = [Canonical.structuralKey(g1), Canonical.structuralKey(g2)];
		var out = compactParams(result);
		maybeRegisterDirtySpineBool(g1, site, remapped, out);
		return out;
	}

	/**
	 * Rank donors for a site, memoizing cold oracle scores within the generation. Credit-cuts /
	 * NMA paths still preferred; the memo collapses repeat (parent, site, donor) triples under
	 * tournament re-picks.
	 */
	function scoreDonors(
		g1:StrategyGenome,
		site:CatalogEntry,
		sampled:Array<BoolNode>,
		evalFn:StrategyGenome->Float
	):Array<Float> {
		var scores = new Array<Float>();
		var needIdx = new Array<Int>();
		var needDonors = new Array<BoolNode>();
		var needLanes = new IntPairList(sampled.length);
		var needMemoKeys = new IntPairList(sampled.length);
		var sitePrefix = siteDigest(Canonical.structuralKey(g1), site.slot, site.path);
		var donorLanes = Canonical.boolStructuralKeysOf(sampled);
		var mk = new StructuralDigest();
		for (i in 0...sampled.length) {
			mk.reset();
			mk.word(sitePrefix.outA);
			mk.word(sitePrefix.outB);
			mk.word(donorLanes.a(i));
			mk.word(donorLanes.b(i));
			mk.finishWords();
			memoLock.acquire();
			var hit = donorScoreMemo.get(mk.outA, mk.outB);
			memoLock.release();
			if (hit != null) {
				donorScoreMemoHits++;
				scores.push(hit);
			} else {
				scores.push(Math.NaN);
				needIdx.push(i);
				needDonors.push(sampled[i]);
				needLanes.push(donorLanes.a(i), donorLanes.b(i));
				needMemoKeys.push(mk.outA, mk.outB);
			}
		}
		if (needDonors.length == 0) return scores;

		var fresh:Array<Float>;
		var siteRef:CatalogSite = { slot: site.slot, path: site.path };
		var nmaDonors = (Fitness.preferNma && Fitness.nmaTape != null)
			? musescript.evo.nma.NmaAttr.boolDonorScores(g1, siteRef, needDonors, Fitness.nmaTape,
				Fitness.nmaCostBps, Fitness.nmaInitialCash, Fitness.nmaEquityFloor)
			: null;
		if (nmaDonors != null) fresh = nmaDonors;
		else if (AttrPool.isNested()) {
			fresh = Fitness.creditCuts
				? musescript.evo.nma.NmaCreditBank.meansPairs(needLanes)
				: [for (_ in needDonors) 0.0];
		}
		else if (Fitness.creditCuts) {
			if (musescript.evo.nma.NmaCreditBank.warmEnoughPairs(needLanes))
				fresh = musescript.evo.nma.NmaCreditBank.meansPairs(needLanes);
			else
				fresh = AttrPool.map(evalFn, [for (donor in needDonors) withBoolRepl(g1, site, donor)]);
		} else fresh = AttrPool.map(evalFn, [for (donor in needDonors) withBoolRepl(g1, site, donor)]);

		memoLock.acquire();
		for (j in 0...needIdx.length) {
			var s = fresh[j];
			scores[needIdx[j]] = s;
			var ka = needMemoKeys.a(j);
			var kb = needMemoKeys.b(j);
			if (!donorScoreMemo.exists(ka, kb)) donorScoreMemo.set(ka, kb, s);
		}
		memoLock.release();
		return scores;
	}

	/**
	 * Digest of `(parentKey, slot, path)` — the donor memo's per-site prefix, folded once and then
	 * combined with each donor's lanes rather than re-walked per donor.
	 */
	static function siteDigest(parentKey:String, slot:Int, path:GPath):StructuralDigest {
		var d = new StructuralDigest();
		d.str(parentKey);
		d.int(slot);
		for (s in path) d.tag(s == StepA ? "A".code : "B".code);
		return d.finishWords();
	}

	function donorsOfKind(g:StrategyGenome, kind:EKind):Array<Dynamic> {
		if (kind == EBool) {
			if (g.variationCacheGen == cacheGen && g.donorPoolCache != null) return g.donorPoolCache;
			var key = Canonical.structuralKey(g);
			memoLock.acquire();
			var hit = donorPoolMemo.get(key);
			if (hit != null) {
				memoLock.release();
				g.donorPoolCache = hit;
				g.variationCacheGen = cacheGen;
				return hit;
			}
			memoLock.release();
			var out:Array<Dynamic> = [];
			donorsFromBool(out, g.entryLong, EBool);
			donorsFromBool(out, g.entryShort, EBool);
			donorsFromBool(out, g.exitLong, EBool);
			donorsFromBool(out, g.exitShort, EBool);
			memoLock.acquire();
			if (!donorPoolMemo.exists(key)) donorPoolMemo.set(key, out);
			memoLock.release();
			g.donorPoolCache = out;
			g.variationCacheGen = cacheGen;
			return out;
		}
		var out:Array<Dynamic> = [];
		donorsFromBool(out, g.entryLong, kind);
		donorsFromBool(out, g.entryShort, kind);
		donorsFromBool(out, g.exitLong, kind);
		donorsFromBool(out, g.exitShort, kind);
		switch (kind) {
			case EBool:
			case EScalar:
				var sc2:Array<{path:GPath, node:ScalarNode}> = [];
				TreeSurgery.collectScalar(g.size, [], sc2);
				for (e in sc2) out.push(e.node);
			case ESeries:
				var xc2:Array<{path:GPath, node:SeriesNode}> = [];
				TreeSurgery.collectSeriesInScalar(g.size, [], xc2);
				for (e in xc2) out.push(e.node);
		}
		return out;
	}

	/** Pulled out of `donorsOfKind` as a real method (was a local closure allocated fresh on
	 * every call) -- same reasoning as `addBoolSlot`. */
	function donorsFromBool(out:Array<Dynamic>, root:BoolNode, kind:EKind):Void {
		switch (kind) {
			case EBool:
				var bc:Array<{path:GPath, node:BoolNode}> = [];
				TreeSurgery.collectBool(root, [], bc);
				for (e in bc) out.push(e.node);
			case EScalar:
				var sc:Array<{path:GPath, node:ScalarNode}> = [];
				TreeSurgery.collectScalarInBool(root, [], sc);
				for (e in sc) out.push(e.node);
			case ESeries:
				var xc:Array<{path:GPath, node:SeriesNode}> = [];
				TreeSurgery.collectSeriesInBool(root, [], xc);
				for (e in xc) out.push(e.node);
		}
	}

	/** Turn a random `KConst` leaf into a tunable `@param` (structure-preserving) —
	 * musegene/variation.py's `promote_param`. */
	public function promoteParam(g:StrategyGenome):StrategyGenome {
		var catalog = buildCatalog(g).filter(e -> e.kind == EScalar);
		var consts = [];
		for (entry in catalog) {
			var node = scalarAt(g, entry);
			switch (node) {
				case KConst(v): consts.push({ entry: entry, value: v });
				default:
			}
		}
		if (consts.length == 0) return g;
		var pick = consts[rng.int(consts.length)];
		var idx = g.params.length;
		var spec:EvoParam = { name: 'p$idx', defaultValue: Math.round(pick.value * 1000) / 1000,
			min: 0.0, max: 100.0, step: 0.5, tune: "grid" };
		var out = withScalarRepl(g, pick.entry, KParam(idx));
		out.params = g.params.concat([spec]);
		return compactParams(out);
	}

	/**
	 * ES-style (1+1) LOCAL tuning of an EXISTING numeric `EvoParam` -- `EvoParam.min`/`max`
	 * (populated by `mintParam`/`promoteParam` above) are never actually consumed by anything
	 * else: crossover/mutation only ever REPLACE a param reference wholesale via ordinary tree
	 * growth, never locally optimize its value in place. Picks one of `g.params` at random,
	 * perturbs its `defaultValue` by a step scaled to that param's OWN `[min,max]` range (clipped
	 * back into range), and keeps the nudge only if it STRICTLY improves `evalFn`'s score -- a
	 * plain accept/reject (1+1)-ES step. NOT a self-adapting step-size 1/5 rule: that needs
	 * per-param step-size STATE to persist across generations, which doesn't fit this genome's
	 * immutable-value-type architecture cleanly (a fresh genome value every generation, no long-
	 * lived object to hang state off) -- a fixed relative step is still a genuine, useful local
	 * search, just not self-tuning; flagged as a richer follow-up, not blocking this first pass.
	 *
	 * `esRng` is passed in (not `this.rng`) so the caller (EvolutionEngine.step) can keep this on
	 * its OWN dedicated stream (RngStreams.ES_NUDGE) -- see RngStreams.hx's doc comment for why
	 * that isolation matters.
	 */
	public function esNudgeParam(g:StrategyGenome, evalFn:StrategyGenome->Float, esRng:Rand):StrategyGenome {
		if (g.params.length == 0) return g;
		var idx = esRng.int(g.params.length);
		var p = g.params[idx];
		var range = p.max - p.min;
		if (range <= 0) return g;
		var step = (esRng.float() * 2 - 1) * range * 0.1; // +/- 10% of the param's own range
		var nudged = Math.max(p.min, Math.min(p.max, p.defaultValue + step));
		if (nudged == p.defaultValue) return g;
		var newParams = g.params.copy();
		newParams[idx] = { name: p.name, defaultValue: nudged, min: p.min, max: p.max, step: p.step, tune: p.tune };
		var candidate = copyGenome(g);
		candidate.params = newParams;
		var baseline = evalFn(g);
		var challenger = evalFn(candidate);
		if (challenger <= baseline) return g;
		candidate.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		return candidate;
	}

	function scalarAt(g:StrategyGenome, entry:CatalogEntry):ScalarNode {
		var root:BoolNode = switch (entry.slot) {
			case 0: g.entryLong;
			case 1: g.entryShort;
			case 2: g.exitLong;
			case 3: g.exitShort;
			default: null;
		};
		if (entry.slot == 4) {
			var sc:Array<{path:GPath, node:ScalarNode}> = [];
			TreeSurgery.collectScalar(g.size, [], sc);
			for (e in sc) if (samePath(e.path, entry.path)) return e.node;
			throw "scalarAt: path not found in size";
		}
		var sc2:Array<{path:GPath, node:ScalarNode}> = [];
		TreeSurgery.collectScalarInBool(root, [], sc2);
		for (e in sc2) if (samePath(e.path, entry.path)) return e.node;
		throw "scalarAt: path not found in bool slot";
	}

	static function samePath(a:GPath, b:GPath):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length) if (a[i] != b[i]) return false;
		return true;
	}

	// ---- param-ref bookkeeping (KParam only ever appears inside ScalarNode subtrees) ----

	static function paramRefsInScalar(n:ScalarNode, out:Array<Int>):Void {
		switch (n) {
			case KConst(_) | KFeature(_) | KSeries(_) | KLookback(_, _):
			case KParam(i): out.push(i);
			case KArith(_, a, b): paramRefsInScalar(a, out); paramRefsInScalar(b, out);
			case KHole(inner): paramRefsInScalar(inner, out);
		}
	}

	static function paramRefsInBool(n:BoolNode, out:Array<Int>):Void {
		switch (n) {
			case BCross(_, _, _) | BTrend(_, _, _):
			case BCmp(_, a, b): paramRefsInScalar(a, out); paramRefsInScalar(b, out);
			case BAnd(a, b) | BOr(a, b): paramRefsInBool(a, out); paramRefsInBool(b, out);
			case BNot(a): paramRefsInBool(a, out);
			case BHole(inner): paramRefsInBool(inner, out);
		}
	}

	static function remapScalar(n:ScalarNode, mapping:ParamMapping):ScalarNode {
		return switch (n) {
			case KConst(v): KConst(v);
			case KFeature(f): KFeature(f);
			case KSeries(s): KSeries(s);
			case KLookback(s, k): KLookback(s, k);
			case KParam(i): KParam(mapping.get(i));
			case KArith(op, a, b): KArith(op, remapScalar(a, mapping), remapScalar(b, mapping));
			case KHole(inner): KHole(remapScalar(inner, mapping));
		};
	}

	static function remapBool(n:BoolNode, mapping:ParamMapping):BoolNode {
		return switch (n) {
			case BCross(d, a, b): BCross(d, a, b);
			case BCmp(op, a, b): BCmp(op, remapScalar(a, mapping), remapScalar(b, mapping));
			case BTrend(d, s, w): BTrend(d, s, w);
			case BAnd(a, b): BAnd(remapBool(a, mapping), remapBool(b, mapping));
			case BOr(a, b): BOr(remapBool(a, mapping), remapBool(b, mapping));
			case BNot(a): BNot(remapBool(a, mapping));
			case BHole(inner): BHole(remapBool(inner, mapping));
		};
	}

	/** Builds a fresh-index mapping for `refs` (donor's param indices) starting at `offset` in
	 * the recipient's space, appending copied specs (from `sourceParams`) into `extra` as a
	 * side effect — mirrors musegene/variation.py's `_import_params`. */
	static function remapOffsets(refs:Array<Int>, offset:Int, extra:Array<EvoParam>,
			sourceParams:Array<EvoParam>):ParamMapping {
		var uniq:Array<Int> = [];
		for (r in refs) if (uniq.indexOf(r) < 0) uniq.push(r);
		uniq.sort((a, b) -> a - b);
		var mapping = new ParamMapping();
		for (i in 0...uniq.length) {
			var old = uniq[i];
			mapping.set(old, offset + i);
			var src = old < sourceParams.length ? sourceParams[old] :
				{ name: 'p$old', defaultValue: 0.0, min: 0.0, max: 100.0, step: 0.5, tune: "grid" };
			extra.push({ name: 'p${offset + i}', defaultValue: src.defaultValue, min: src.min,
				max: src.max, step: src.step, tune: src.tune });
		}
		return mapping;
	}

	/** Drop `@param`s no leaf references and renumber the survivors p0..pk — musegene/
	 * variation.py's `compact_params`. */
	public function compactParams(g:StrategyGenome):StrategyGenome {
		// Param-free genomes (common under RegistryPalette terminals): nothing to compact, and
		// the five-root paramRefs walk was pure tax on every mutate/XO child.
		if (g.params == null || g.params.length == 0) return g;
		var refs = [];
		paramRefsInBool(g.entryLong, refs);
		paramRefsInBool(g.entryShort, refs);
		paramRefsInBool(g.exitLong, refs);
		paramRefsInBool(g.exitShort, refs);
		paramRefsInScalar(g.size, refs);
		var used:Array<Int> = [];
		for (r in refs) if (used.indexOf(r) < 0) used.push(r);
		used.sort((a, b) -> a - b);

		var tight = used.length == g.params.length;
		if (tight) for (i in 0...used.length) if (used[i] != i) tight = false;
		if (tight) return g;

		var mapping = new ParamMapping();
		var newParams:Array<EvoParam> = [];
		for (i in 0...used.length) {
			var old = used[i];
			mapping.set(old, i);
			if (old < g.params.length) {
				var src = g.params[old];
				newParams.push({ name: 'p$i', defaultValue: src.defaultValue, min: src.min,
					max: src.max, step: src.step, tune: src.tune });
			}
		}
		return {
			entryLong: remapBool(g.entryLong, mapping),
			entryShort: remapBool(g.entryShort, mapping),
			exitLong: remapBool(g.exitLong, mapping),
			exitShort: remapBool(g.exitShort, mapping),
			size: remapScalar(g.size, mapping),
			params: newParams,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			// `projections` IS genome identity (StrategyGenome doc): elites/splices must keep their
			// host decls. This non-tight rebuild used to omit the field, silently dropping every
			// PSHost projection whenever a mutate/XO changed the param count — the real cause of
			// host genomes draining from the pop after gen 0 (reinject was only a bandage). Live
			// projections are PSHost (no param refs / nodes), so verbatim is correct here; the
			// param `mapping` only touches the five policy roots. (PSPoint/PSNoise carry param
			// refs and would need remapping + inclusion in `used`, but those are test-only today.)
			projections: g.projections
		};
	}

	// ---- profit-attribution-guided mutation ----------------------------------------------

	/**
	 * `pointMutate`, but the mutation SITE is chosen by ablation-based attribution instead of a
	 * uniform random pick: every BoolNode position in `g` (every AND/OR/NOT/comparison/cross/
	 * trend condition across the 4 entry/exit slots) gets temporarily replaced with an
	 * always-true condition and re-scored via `evalFn` (a real fitness oracle — the same "js"
	 * `Fitness.evaluate` path this whole system already trusts, now that it's fixed to actually
	 * run the backtest). The fitness DELTA (baseline minus ablated) is that node's estimated
	 * "profit contribution": a node whose neutralization tanks fitness is pulling real weight
	 * and gets protected; a node whose neutralization barely matters (or even helps) is dead
	 * weight or actively harmful, and becomes a HIGH-PRIORITY mutation target.
	 *
	 * Ranked, not scaled, on purpose: Sharpe deltas from ablating different nodes have wildly
	 * different natural scale (a core entry gate vs. a redundant OR clause), and an ablation can
	 * legitimately push a genome to `Fitness.NEG_INF` (e.g. an entry condition that becomes
	 * `true` for every bar and blows past a min-trades/behavior sanity limit) — raw-magnitude
	 * normalization would be dominated by outliers. Rank-based weighting treats "least
	 * important" and "most important" consistently regardless of how big the gap is.
	 *
	 * Only BoolNode positions are attributed (not Scalar/Series) — that's where actual trading
	 * DECISIONS live (which conditions gate entries/exits), and it keeps the extra cost bounded
	 * to O(bool nodes in g) extra evaluations per call, not O(every node). Falls back to the
	 * plain uniform `pointMutate` when `g` has no BoolNode positions (shouldn't happen — every
	 * genome has 4 bool slots — but kept as a defensive no-op path) or with a small fixed
	 * probability regardless, to keep some pure-exploration pressure in the mix rather than
	 * mutation becoming ENTIRELY exploitation-driven.
	 */
	public function attributedPointMutate(g:StrategyGenome, evalFn:StrategyGenome->Float, maxDepth:Int = 2):StrategyGenome {
		// Semantic-RDO flap: directed site+replacement via NMA lastSeries vs desired semantics.
		if (Fitness.semanticRdoProb > 0 && Fitness.preferNma && Fitness.nmaTape != null
				&& rng.float() < Fitness.semanticRdoProb) {
			var rdo = musescript.evo.nma.NmaSemanticRdo.tryMutate(g, function(d) return growBool(d), rng, maxDepth);
			if (rdo != null) return compactParams(rdo);
		}
		var catalog = buildBoolCatalog(g);
		var boolEntries = catalog;
		if (boolEntries.length == 0 || rng.float() < 0.2) return pointMutate(g, maxDepth);

		var pack = computeSiteDeltas(g, boolEntries, evalFn);
		var baseline = pack.baseline;
		var deltas = pack.deltas;

		// P2: blend ablation Δ with durable credit prior (high credit → protect). Bank-only
		// packs already carry means in `deltas` — blending again is a no-op on rank order.
		var importance:Array<Float>;
		if (Math.isNaN(baseline)) {
			importance = deltas;
		} else {
			var priors = musescript.evo.nma.NmaCreditBank.meansPairs(pack.keys);
			importance = [for (i in 0...boolEntries.length) deltas[i] + priors[i]];
		}

		var order = [for (i in 0...boolEntries.length) i];
		order.sort((a, b) -> importance[a] < importance[b] ? -1 : importance[a] > importance[b] ? 1 : 0);
		var weights = [for (_ in 0...boolEntries.length) 1.0];
		for (rank in 0...order.length) weights[order[rank]] = order.length - rank; // rank 0 (least important) -> highest weight

		var entry = boolEntries[weightedPickIndex(weights)];
		var d = rng.int(maxDepth + 1);
		var kSpec = Fitness.speculativeGrowthK;
		var grown:BoolNode;
		var tagOut:Array<String> = [];
		var winnerScore:Null<Float> = null;
		var winnerBaseline:Null<Float> = null;
		if (kSpec > 1 && Fitness.preferNma && Fitness.nmaTape != null) {
			var cands:Array<BoolNode> = [];
			var tagBags:Array<Array<String>> = [];
			for (_ in 0...kSpec) {
				var tags:Array<String> = [];
				cands.push(growBool(d, null, tags));
				tagBags.push(tags);
			}
			var site:CatalogSite = { slot: entry.slot, path: entry.path };
			var robust = musescript.evo.nma.NmaAttr.boolReplacementRobustScores(
				g, site, cands, Fitness.nmaTape,
				Fitness.speculativeGrowthWindows,
				Fitness.speculativeGrowthWindowLambda,
				Fitness.speculativeGrowthParsimonyLambda,
				Fitness.nmaCostBps, Fitness.nmaInitialCash, Fitness.nmaEquityFloor);
			if (robust != null && robust.scores.length == cands.length) {
				var scores = robust.scores;
				var pick = 0;
				var best = Fitness.NEG_INF;
				for (i in 0...scores.length) {
					var s = scores[i];
					if (s != Fitness.NEG_INF && !Math.isNaN(s) && s > best) {
						best = s;
						pick = i;
					}
				}
				// Acceptance gate: no forced mutation when all K candidates lose to the parent.
				if (best < robust.baseline + Fitness.speculativeGrowthMinDelta) return g;
				grown = cands[pick];
				tagOut = tagBags[pick];
				winnerScore = scores[pick];
				winnerBaseline = robust.baseline;
			} else {
				grown = growBool(d, null, tagOut);
			}
		} else {
			grown = growBool(d, null, tagOut);
		}
		var mutated = withBoolRepl(g, entry, grown);
		mutated.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		var out = compactParams(mutated);
		maybeRegisterDirtySpineBool(g, entry, grown, out);
		if (tagOut.length > 0) {
			// Warm credit-cuts leaves baseline as NaN: ranking used bank means and never scored the
			// parent. Paying evalFn(g)+evalFn(out) here re-introduced the exact serial oracle tax
			// the warm path exists to remove — nearly two backtests per mutated child, which at
			// pop=1000 dominated step even after ablations went to zero. Skip the tuner update on
			// that path; cold-path gens (and speculative-growth's already-scored winner) still
			// reward. Continuous innovation keeps getting credit deposits from NmaAttr ablations
			// while the bank is filling.
			if (winnerScore != null && winnerBaseline != null) {
				if (winnerBaseline != Fitness.NEG_INF && winnerScore != Fitness.NEG_INF) {
					var delta = winnerScore - winnerBaseline;
					for (tag in tagOut) {
						var parts = tag.split(":");
						tuner.reward(parts[0], parts[1], delta);
					}
					var gw = Canonical.boolStructuralWords(grown);
					musescript.evo.nma.NmaCreditBank.depositWords(gw.a, gw.b, delta);
				}
			} else if (baseline == baseline && baseline != Fitness.NEG_INF) {
				var childFitness = evalFn(out);
				if (childFitness != Fitness.NEG_INF) {
					var delta2 = childFitness - baseline;
					for (tag in tagOut) {
						var parts2 = tag.split(":");
						tuner.reward(parts2[0], parts2[1], delta2);
					}
				}
			}
		}
		return out;
	}

	/**
	 * Baseline + per-bool-site ablation deltas, memoized by structural key within a generation
	 * (PLAN_EVO_SPEED P1.1). Same ranking signal as the old inline paths in attributed mutate/XO.
	 * `keys` are the bool structural digest lanes for each site (same order) — callers reuse them
	 * for credit priors instead of re-hashing.
	 */
	/** Digest lanes for each catalog site's bool subtree, in `boolEntries` order. */
	function siteKeysOf(g:StrategyGenome, boolEntries:Array<CatalogEntry>):IntPairList {
		if (g.variationCacheGen == cacheGen && g.boolSiteKeysCache != null
			&& g.boolSiteKeysCache.length == boolEntries.length
			&& g.boolCatalogCache == boolEntries)
			return g.boolSiteKeysCache;
		var out = siteKeysFresh(g, boolEntries);
		if (g.boolCatalogCache == boolEntries) {
			g.boolSiteKeysCache = out;
			g.variationCacheGen = cacheGen;
		}
		return out;
	}

	function siteKeysFresh(g:StrategyGenome, boolEntries:Array<CatalogEntry>):IntPairList {
		var out = new IntPairList(boolEntries.length);
		var d = new StructuralDigest();
		for (e in boolEntries)
			Canonical.boolStructuralInto(out, TreeSurgery.getBool(boolRootOf(g, e.slot), e.path), d);
		return out;
	}

	function computeSiteDeltas(g:StrategyGenome, boolEntries:Array<CatalogEntry>, evalFn:StrategyGenome->Float):{baseline:Float, deltas:Array<Float>, keys:IntPairList} {
		var memoKey = Canonical.structuralKey(g);
		memoLock.acquire();
		var hit = siteDeltaMemo.get(memoKey);
		if (hit != null) {
			siteDeltaMemoHits++;
			memoLock.release();
			return hit;
		}
		memoLock.release();

		var baseline:Float;
		var deltas:Array<Float>;
		var keys:IntPairList;
		var nmaPack = (Fitness.preferNma && Fitness.nmaTape != null)
			? musescript.evo.nma.NmaAttr.boolSiteDeltas(g, [for (e in boolEntries) ({slot: e.slot, path: e.path} : CatalogSite)], Fitness.nmaTape,
				Fitness.nmaCostBps, Fitness.nmaInitialCash, Fitness.nmaEquityFloor)
			: null;
		if (nmaPack != null) {
			baseline = nmaPack.baseline;
			deltas = nmaPack.deltas;
			keys = nmaPack.keys;
		} else if (Fitness.creditCuts || AttrPool.isNested()) {
			// Nested workers: NEVER AttrPool.map(evalFn) — it serializes into full backtests per
			// site and was the step.xo wall once NMA coverage rose. Bank prior / zeros only.
			keys = siteKeysOf(g, boolEntries);
			if (Fitness.creditCuts && musescript.evo.nma.NmaCreditBank.warmEnoughPairs(keys)) {
				baseline = Math.NaN;
				deltas = musescript.evo.nma.NmaCreditBank.meansPairs(keys);
			} else if (AttrPool.isNested()) {
				baseline = Math.NaN;
				deltas = Fitness.creditCuts
					? musescript.evo.nma.NmaCreditBank.meansPairs(keys)
					: [for (_ in boolEntries) 0.0];
			} else {
				var alwaysTrue:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
				var batch = new Array<StrategyGenome>();
				batch.push(g);
				for (e in boolEntries) batch.push(withBoolRepl(g, e, alwaysTrue));
				var scores = AttrPool.map(evalFn, batch);
				baseline = scores[0];
				deltas = [for (i in 0...boolEntries.length) baseline - scores[i + 1]];
			}
		} else {
			keys = siteKeysOf(g, boolEntries);
			var alwaysTrue:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
			var batch = new Array<StrategyGenome>();
			batch.push(g);
			for (e in boolEntries) batch.push(withBoolRepl(g, e, alwaysTrue));
			var scores = AttrPool.map(evalFn, batch);
			baseline = scores[0];
			deltas = [for (i in 0...boolEntries.length) baseline - scores[i + 1]];
		}
		var pack = { baseline: baseline, deltas: deltas, keys: keys };
		memoLock.acquire();
		// Another worker may have filled this key while we computed; keep the first writer.
		if (!siteDeltaMemo.exists(memoKey)) siteDeltaMemo.set(memoKey, pack);
		memoLock.release();
		return pack;
	}

	/**
	 * When `--nma-dirty-spine` is armed: warm parent working copy if needed, spine-splice `repl`
	 * into a child NMA tree sharing sibling memos, register under `child`'s structural key.
	 * No-op when flag off / tape missing / unsupported genome / param-length mismatch.
	 *
	 * «δεσποίνας δὲ ὑπὸ κόλπον ἔδυν χθονίας βασιλείας.»
	 */
	function maybeRegisterDirtySpineBool(parent:StrategyGenome, entry:CatalogEntry, repl:BoolNode, child:StrategyGenome):Void {
		if (!Fitness.nmaDirtySpine || !Fitness.preferNma || Fitness.nmaWorking == null || Fitness.nmaTape == null) return;
		if (entry.kind != EBool) return;
		var parentPack = Fitness.workingGet(Canonical.structuralKey(parent));
		if (parentPack == null)
			parentPack = musescript.evo.nma.NmaDirtySpine.warmAndPut(parent, Fitness.nmaTape,
				Fitness.nmaCostBps, Fitness.nmaInitialCash, Fitness.nmaEquityFloor);
		if (parentPack != null) {
			// `compactParams` may remap KParam indices after the original replacement was built.
			// Register the actual normalized subtree from `child`, not the pre-compact `repl`.
			var normalizedRepl = TreeSurgery.getBool(boolRootOf(child, entry.slot), entry.path);
			musescript.evo.nma.NmaDirtySpine.spliceAndRegister(
				parentPack, entry.slot, entry.path, normalizedRepl, child);
		}
	}

	static function boolRootOf(g:StrategyGenome, slot:Int):BoolNode {
		return switch (slot) {
			case 0: g.entryLong;
			case 1: g.entryShort;
			case 2: g.exitLong;
			case 3: g.exitShort;
			default: g.entryLong;
		};
	}

	function weightedPickIndex(weights:Array<Float>):Int {
		var total = 0.0;
		for (w in weights) total += w;
		if (total <= 0) return rng.int(weights.length);
		var r = rng.float() * total;
		var acc = 0.0;
		for (i in 0...weights.length) {
			acc += weights[i];
			if (r <= acc) return i;
		}
		return weights.length - 1;
	}

	// ---- back-compat names (EvolutionEngine calls these) — now backed by the real operators ----

	/**
	 * Probability a blind `mutate` tries host projection / soft-φ growth first.
	 * CorpusEvoRun `--ew-host` raises this so fusion actually iterates.
	 */
	public static var hostMutateRate:Float = 0.12;

	public function mutate(g:StrategyGenome):StrategyGenome {
		// Soft forecast-gene / PSHost growth stays off the hot path unless gated on — default ~12%
		// of blind mutates may touch host projections / φ deltas without rewriting hard EW rules.
		var rate = hostMutateRate;
		if (rate < 0) rate = 0;
		if (rate > 1) rate = 1;
		if (rng.float() < rate) {
			var h = mutateHostProjection(g);
			if (h != g) {
				if (logHostProjection)
					logHostMutate(g, h);
				return h;
			}
		}
		return pointMutate(g);
	}
	public function crossover(a:StrategyGenome, b:StrategyGenome):StrategyGenome return subtreeCrossover(a, b);

	/** Host kinds Variation may assign to `PSHost` (soft backend choice only). */
	public static var HOST_KINDS:Array<String> = ["lattice", "mcmc"];

	/** When true, print `[ew-host] mutate …` lines (CorpusEvoRun `--ew-host` turns this on). */
	public static var logHostProjection:Bool = false;

	/** Fan-reduction fields TradeLogic may grow against a host projection. */
	static var HOST_FIELDS:Array<String> = [
		"p50", "spread", "prob_up", "inv", "dist_inv", "entropy", "nest", "top_mass"
	];

	/**
	 * Grow or mutate `PSHost` projections + soft `phiDeltas`. Never invents hard-rule constants.
	 * Returns `g` unchanged when there is nothing useful to do.
	 */
	public function mutateHostProjection(g:StrategyGenome):StrategyGenome {
		var o = copyGenome(g);
		var roll = rng.float();
		if (o.projections == null || o.projections.length == 0 || roll < 0.35) {
			return attachHostProjection(o);
		}
		var idx = rng.int(o.projections.length);
		var p = o.projections[idx];
		switch (p.sampler) {
			case PSHost(kind):
				var np = copyProj(p);
				if (rng.float() < 0.4) {
					// Flip lattice ↔ mcmc backend.
					var next = kind == "mcmc" ? "lattice" : "mcmc";
					np.sampler = PSHost(next);
					if (next == "mcmc" && np.samples < 2) np.samples = 4 + rng.int(5);
				} else if (rng.float() < 0.5) {
					np.phiDeltas = mutatePhiDeltas(np.phiDeltas);
				} else {
					np.seed = np.seed ^ (rng.int(0x7fffffff) + 1);
					if (np.samples < 1) np.samples = 1;
				}
				o.projections = o.projections.copy();
				o.projections[idx] = np;
				// φ / backend churn with no SProj read cannot move trading or projScore — soft-wire.
				if (ProjectionProvider.hostProjRefs(o).length == 0)
					return attachHostProjection(o);
				o.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
				return compactParams(o);
			default:
				return attachHostProjection(o);
		}
	}

	/** Ensure a host projection exists and wire one `SProj` read into entryLong when absent. */
	public function attachHostProjection(g:StrategyGenome):StrategyGenome {
		var o = copyGenome(g);
		var name = "ew_0";
		var hasHost = false;
		if (o.projections != null) {
			for (p in o.projections) {
				switch (p.sampler) {
					case PSHost(_):
						hasHost = true;
						name = p.name;
					default:
				}
				if (hasHost) break;
			}
		}
		if (!hasHost) {
			var kind = rng.pick(HOST_KINDS);
			var decl = ProjectionProvider.ewDecl(
				name, 5, kind, rng.int(10000),
				mutatePhiDeltas(null),
				kind == "mcmc" ? 4 + rng.int(5) : 1
			);
			o.projections = o.projections != null ? o.projections.concat([decl]) : [decl];
		}
		// Soft-wire a host field into entryLong if the policy never reads this host.
		var refs = ProjectionProvider.hostProjRefs(o);
		if (refs.length == 0) {
			var field = rng.pick(HOST_FIELDS);
			var cmp = rng.pick(Palette.CMP);
			o.entryLong = BAnd(o.entryLong,
				BCmp(cmp, KSeries(SProj(name, field)), KSeries(SPrice("close"))));
		}
		o.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		return compactParams(o);
	}

	static function logHostMutate(before:StrategyGenome, after:StrategyGenome):Void {
		var decl = ProjectionProvider.firstPsHostDecl(after);
		var kind = "?";
		var phi = "-";
		var samples = 0;
		if (decl != null) {
			kind = switch (decl.sampler) { case PSHost(k): k; default: "?"; };
			phi = ProjectionProvider.phiKeyOf(decl.phiDeltas);
			if (phi == null) phi = "-";
			samples = decl.samples;
		}
		var bname = before.name != null ? before.name : "?";
		var aname = after.name != null ? after.name : "?";
		Sys.println('[ew-host] mutate from=$bname to=$aname kind=$kind samples=$samples phi=$phi digest=${decl != null ? ProjectionProvider.declDigest(decl) : "-"}');
	}

	/** Small Gaussian steps on soft φ residuals; clamp magnitudes so soft scores stay sane. */
	public function mutatePhiDeltas(?cur:Map<String, Float>):Map<String, Float> {
		var out:Map<String, Float> = cur != null ? copyFloatMap(cur) : new Map();
		var key = rng.pick(ProjectionProvider.SOFT_PHI_KEYS);
		var step = (rng.float() - 0.5) * 0.08; // ±0.04 typical
		var prev = out.exists(key) ? out.get(key) : 0.0;
		var next = prev + step;
		if (next > 0.25) next = 0.25;
		if (next < -0.25) next = -0.25;
		if (Math.abs(next) < 1e-6) out.remove(key);
		else out.set(key, next);
		return out;
	}

	static function copyProj(p:ProjectionDecl):ProjectionDecl {
		return {
			name: p.name, kind: p.kind, horizon: p.horizon, sampler: p.sampler,
			samples: p.samples, seed: p.seed,
			phiDeltas: p.phiDeltas != null ? copyFloatMap(p.phiDeltas) : null
		};
	}

	static function copyFloatMap(m:Map<String, Float>):Map<String, Float> {
		var out = new Map<String, Float>();
		for (k => v in m) out.set(k, v);
		return out;
	}
}
