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

typedef CatalogEntry = {
	slot:Int, // 0=entryLong 1=entryShort 2=exitLong 3=exitShort 4=size
	kind:EKind,
	path:GPath
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

	public function new(seed:Int, ?indicatorPool:Array<String>) {
		rng = new Rand(seed);
		this.indicatorPool = indicatorPool != null ? indicatorPool : Palette.INDS;
	}

	// ---- growth (unchanged shape, BNot/BTrend added to close the reachability gap found
	// while surveying evolution-system coverage: both were typed but never generated) ----

	function growSeries(depth:Int):SeriesNode {
		if (depth <= 0 || rng.float() < 0.4)
			return SPrice(rng.pick(Palette.FIELDS));
		return SInd(rng.pick(indicatorPool), rng.pick(Palette.FIELDS), rng.pick(Palette.WINDOWS), null);
	}

	function growScalar(depth:Int, ?pool:Array<EvoParam>):ScalarNode {
		if (depth <= 0 || rng.float() < 0.5) {
			if (pool != null && rng.float() < 0.15) return mintParam(pool);
			return KSeries(growSeries(0));
		}
		if (rng.float() < 0.35) return KSeries(growSeries(0));
		if (pool != null && rng.float() < 0.2) return mintParam(pool);
		if (rng.float() < 0.5) return KConst(rng.float() * 4 - 2);
		return KArith(rng.pick(Palette.ARITH), growScalar(depth - 1, pool), growScalar(depth - 1, pool));
	}

	/** `growBool`'s terminal case now includes `BTrend` alongside `BCross`/`BCmp`, and the
	 * recursive case can produce `BNot` — both existed in the type system but were previously
	 * structurally unreachable (found while surveying evolution-system coverage against the
	 * full stdlib). */
	function growBool(depth:Int, ?pool:Array<EvoParam>):BoolNode {
		if (depth <= 0 || rng.float() < 0.45) {
			var r = rng.float();
			if (r < 0.4) return BCross(rng.pick(Palette.CROSS), growSeries(1), growSeries(1));
			if (r < 0.7) return BCmp(rng.pick(Palette.CMP), growScalar(1, pool), growScalar(1, pool));
			return BTrend(rng.pick(Palette.CROSS), growSeries(1), rng.pick(Palette.WINDOWS));
		}
		var r = rng.float();
		if (r < 0.4) return BAnd(growBool(depth - 1, pool), growBool(depth - 1, pool));
		if (r < 0.8) return BOr(growBool(depth - 1, pool), growBool(depth - 1, pool));
		return BNot(growBool(depth - 1, pool));
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

	function buildCatalog(g:StrategyGenome):Array<CatalogEntry> {
		var out:Array<CatalogEntry> = [];
		function addBoolSlot(slot:Int, root:BoolNode):Void {
			var bc:Array<{path:GPath, node:BoolNode}> = [];
			TreeSurgery.collectBool(root, [], bc);
			for (e in bc) out.push({ slot: slot, kind: EBool, path: e.path });
			var sc:Array<{path:GPath, node:ScalarNode}> = [];
			TreeSurgery.collectScalarInBool(root, [], sc);
			for (e in sc) out.push({ slot: slot, kind: EScalar, path: e.path });
			var xc:Array<{path:GPath, node:SeriesNode}> = [];
			TreeSurgery.collectSeriesInBool(root, [], xc);
			for (e in xc) out.push({ slot: slot, kind: ESeries, path: e.path });
		}
		addBoolSlot(0, g.entryLong);
		addBoolSlot(1, g.entryShort);
		addBoolSlot(2, g.exitLong);
		addBoolSlot(3, g.exitShort);
		var sc2:Array<{path:GPath, node:ScalarNode}> = [];
		TreeSurgery.collectScalar(g.size, [], sc2);
		for (e in sc2) out.push({ slot: 4, kind: EScalar, path: e.path });
		var xc2:Array<{path:GPath, node:SeriesNode}> = [];
		TreeSurgery.collectSeriesInScalar(g.size, [], xc2);
		for (e in xc2) out.push({ slot: 4, kind: ESeries, path: e.path });
		return out;
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

	function donorsOfKind(g:StrategyGenome, kind:EKind):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		function fromBool(root:BoolNode):Void {
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
		fromBool(g.entryLong);
		fromBool(g.entryShort);
		fromBool(g.exitLong);
		fromBool(g.exitShort);
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
		}
	}

	static function paramRefsInBool(n:BoolNode, out:Array<Int>):Void {
		switch (n) {
			case BCross(_, _, _) | BTrend(_, _, _):
			case BCmp(_, a, b): paramRefsInScalar(a, out); paramRefsInScalar(b, out);
			case BAnd(a, b) | BOr(a, b): paramRefsInBool(a, out); paramRefsInBool(b, out);
			case BNot(a): paramRefsInBool(a, out);
		}
	}

	static function remapScalar(n:ScalarNode, mapping:Map<Int, Int>):ScalarNode {
		return switch (n) {
			case KConst(v): KConst(v);
			case KFeature(f): KFeature(f);
			case KSeries(s): KSeries(s);
			case KLookback(s, k): KLookback(s, k);
			case KParam(i): KParam(mapping.exists(i) ? mapping.get(i) : i);
			case KArith(op, a, b): KArith(op, remapScalar(a, mapping), remapScalar(b, mapping));
		};
	}

	static function remapBool(n:BoolNode, mapping:Map<Int, Int>):BoolNode {
		return switch (n) {
			case BCross(d, a, b): BCross(d, a, b);
			case BCmp(op, a, b): BCmp(op, remapScalar(a, mapping), remapScalar(b, mapping));
			case BTrend(d, s, w): BTrend(d, s, w);
			case BAnd(a, b): BAnd(remapBool(a, mapping), remapBool(b, mapping));
			case BOr(a, b): BOr(remapBool(a, mapping), remapBool(b, mapping));
			case BNot(a): BNot(remapBool(a, mapping));
		};
	}

	/** Builds a fresh-index mapping for `refs` (donor's param indices) starting at `offset` in
	 * the recipient's space, appending copied specs (from `sourceParams`) into `extra` as a
	 * side effect — mirrors musegene/variation.py's `_import_params`. */
	static function remapOffsets(refs:Array<Int>, offset:Int, extra:Array<EvoParam>,
			sourceParams:Array<EvoParam>):Map<Int, Int> {
		var uniq = [];
		var seen = new Map<Int, Bool>();
		for (r in refs) if (!seen.exists(r)) { seen.set(r, true); uniq.push(r); }
		uniq.sort((a, b) -> a - b);
		var mapping = new Map<Int, Int>();
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
		var seen = new Map<Int, Bool>();
		for (r in refs) seen.set(r, true);
		var used = [for (k in seen.keys()) k];
		used.sort((a, b) -> a - b);

		var tight = used.length == g.params.length;
		if (tight) for (i in 0...used.length) if (used[i] != i) tight = false;
		if (tight) return g;

		var mapping = new Map<Int, Int>();
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

	// ---- back-compat names (EvolutionEngine calls these) — now backed by the real operators ----

	public function mutate(g:StrategyGenome):StrategyGenome return pointMutate(g);
	public function crossover(a:StrategyGenome, b:StrategyGenome):StrategyGenome return subtreeCrossover(a, b);
}
