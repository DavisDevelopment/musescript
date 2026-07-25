package musescript.evo;

import musescript.evo.TreeSurgery;

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
 */
enum EKind {
	EBool;
	EScalar;
	ESeries;
}

@:structInit
class CatalogEntry {
	public var slot:Int; // 0=entryLong 1=entryShort 2=exitLong 3=exitShort 4=size
	public var kind:EKind;
	public var path:GPath;
}

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

	public function new(seed:Int, ?indicatorPool:Array<String>, ?tuner:GrowthWeights) {
		rng = new Rand(seed);
		this.indicatorPool = indicatorPool != null ? indicatorPool : Palette.INDS;
		this.tuner = tuner != null ? tuner : new GrowthWeights();
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
		// `armed = !templated`: an untemplated genome starts (and stays) fully recordable, byte-
		// identical to this function's behavior before holes existed. A templated genome starts
		// UNrecordable and only becomes recordable once TreeSurgery's collect* walk crosses an
		// actual BHole/KHole boundary -- see TreeSurgery.collectBool's doc comment.
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
			lineage: g.lineage != null ? g.lineage.copy() : [], seedOrigin: g.seedOrigin };
	}

	static function setEntryLong(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.entryLong = v; return o; }
	static function setEntryShort(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.entryShort = v; return o; }
	static function setExitLong(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.exitLong = v; return o; }
	static function setExitShort(g:StrategyGenome, v:BoolNode):StrategyGenome { var o = copyGenome(g); o.exitShort = v; return o; }
	static function setSize(g:StrategyGenome, v:ScalarNode):StrategyGenome { var o = copyGenome(g); o.size = v; return o; }

	// ---- operators ----

	/** Replace one random subtree (any slot, any depth) with a fresh same-typed subtree —
	 * musegene/variation.py's `point_mutate`, ported via TreeSurgery paths instead of Python's
	 * identity-based node replacement. */
	public function pointMutate(g:StrategyGenome, maxDepth:Int = 2):StrategyGenome {
		var catalog = buildCatalog(g);
		if (catalog.length == 0) return g;
		var entry = catalog[rng.int(catalog.length)];
		var d = rng.int(maxDepth + 1);
		var mutated = switch (entry.kind) {
			case EBool: withBoolRepl(g, entry, growBool(d));
			case EScalar: withScalarRepl(g, entry, growScalar(d));
			case ESeries: withSeriesRepl(g, entry, growSeries(d));
		};
		mutated.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		return compactParams(mutated);
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
				withBoolRepl(g1, site, remapBool(donor, mapping));
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
	public function attributedSubtreeCrossover(g1:StrategyGenome, g2:StrategyGenome, evalFn:StrategyGenome->Float, donorSampleCap:Int = 6):StrategyGenome {
		var catalog1 = buildCatalog(g1);
		var boolSites = [for (e in catalog1) if (e.kind == EBool) e];
		if (boolSites.length == 0 || rng.float() < 0.2) return subtreeCrossover(g1, g2);

		var baseline = evalFn(g1);
		var alwaysTrue:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
		var siteDeltas = [for (e in boolSites) baseline - evalFn(withBoolRepl(g1, e, alwaysTrue))];
		var siteOrder = [for (i in 0...boolSites.length) i];
		siteOrder.sort((a, b) -> siteDeltas[a] < siteDeltas[b] ? -1 : siteDeltas[a] > siteDeltas[b] ? 1 : 0);
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
		var donorScores = [for (donor in sampled) evalFn(withBoolRepl(g1, site, donor))];
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
		var result = withBoolRepl(g1, site, remapBool(donor, mapping));
		result.params = g1.params.concat(extraParams);
		result.lineage = [Canonical.structuralKey(g1), Canonical.structuralKey(g2)];
		return compactParams(result);
	}

	function donorsOfKind(g:StrategyGenome, kind:EKind):Array<Dynamic> {
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
			seedOrigin: g.seedOrigin
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
		var catalog = buildCatalog(g);
		var boolEntries = [for (e in catalog) if (e.kind == EBool) e];
		if (boolEntries.length == 0 || rng.float() < 0.2) return pointMutate(g, maxDepth);

		var baseline = evalFn(g);
		var alwaysTrue:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
		var deltas = [for (e in boolEntries) {
			var f = evalFn(withBoolRepl(g, e, alwaysTrue));
			baseline - f; // larger = more important (protect); smaller/negative = safe to mutate
		}];

		var order = [for (i in 0...boolEntries.length) i];
		order.sort((a, b) -> deltas[a] < deltas[b] ? -1 : deltas[a] > deltas[b] ? 1 : 0);
		var weights = [for (_ in 0...boolEntries.length) 1.0];
		for (rank in 0...order.length) weights[order[rank]] = order.length - rank; // rank 0 (least important) -> highest weight

		var entry = boolEntries[weightedPickIndex(weights)];
		var d = rng.int(maxDepth + 1);
		// tagOut captures the outermost growth choice made while building the replacement subtree
		// (e.g. "boolTerm:riskExit") so it can be REWARDED below once the child's real fitness is
		// known -- this is the auto-tuning feedback loop GrowthWeights exists for: the SAME
		// evalFn/baseline this function already computes for ablation-based site TARGETING also
		// closes the loop on WHICH KIND of node evolution should keep reaching for. Targeting
		// itself stays bool-only exactly as before (untouched by this) -- only the reward signal
		// for the tuner is new.
		var tagOut:Array<String> = [];
		var mutated = withBoolRepl(g, entry, growBool(d, null, tagOut));
		mutated.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		var out = compactParams(mutated);
		if (tagOut.length > 0) {
			var childFitness = evalFn(out);
			if (baseline != Fitness.NEG_INF && childFitness != Fitness.NEG_INF) {
				var delta = childFitness - baseline;
				// Credit EVERY choice in the trajectory (not just the outermost) with the SAME
				// delta -- this is what actually lets riskExit/multiOutput/scalarTerm/scalarRecurse
				// ever move at all (see growScalar's doc comment for the empirical proof they
				// previously never did): the whole subtree that got spliced in is what produced
				// this fitness delta, not just its outermost shape.
				for (tag in tagOut) {
					var parts = tag.split(":");
					tuner.reward(parts[0], parts[1], delta);
				}
			}
		}
		return out;
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

	public function mutate(g:StrategyGenome):StrategyGenome return pointMutate(g);
	public function crossover(a:StrategyGenome, b:StrategyGenome):StrategyGenome return subtreeCrossover(a, b);
}
