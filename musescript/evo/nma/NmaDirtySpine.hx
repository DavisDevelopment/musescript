package musescript.evo.nma;

import musescript.evo.StrategyGenome;
import musescript.evo.BoolNode;
import musescript.evo.Fitness;
import musescript.evo.Canonical;
import musescript.evo.GenomeFeatures;
import musescript.evo.TreeSurgery.GPath;
import musescript.harness.Bar;

/**
 * Live NMA working-copy registry for Variation→Fitness dirty-spine re-eval (spec §6b / §8.3).
 *
 * After a warm `prepare`+`evaluatePrepared`, the genome's NMA tree stays keyed by
 * `Canonical.structuralKey`. A bool-site splice via `NmaSurgery` builds a **new** `NmaGenome`
 * that shares sibling node identity (memos intact) — next `Fitness.evaluate` hits the cache and
 * only recomputes the dirty spine.
 *
 * «ῥάβδος Διονύσου· ἕρπει δράκων διὰ κόλπου.»
 */
class NmaDirtySpine {

	/** Lookup working copy if tape matches. */
	public static function get(g:StrategyGenome, tapeSig:String):Null<NmaWorkingPack> {
		var w = Fitness.workingGet(Canonical.structuralKey(g));
		if (w == null || w.tapeSig != tapeSig) return null;
		return w;
	}

	public static function put(g:StrategyGenome, pack:NmaWorkingPack):Void {
		Fitness.workingPut(Canonical.structuralKey(g), pack);
	}

	/** Warm parent (prepare + one eval) and register. Null if columnar unsupported. */
	public static function warmAndPut(g:StrategyGenome, bars:Array<Bar>,
			?costBps:Float = 0.0, ?initialCash:Float = 100000, ?equityFloor:Float = 0.0):Null<NmaWorkingPack> {
		var built = NmaFitness.prepare(g, bars);
		if (built == null) return null;
		var fr = NmaFitness.evaluatePrepared(built.nma, built.ctx, bars, costBps, initialCash, equityFloor);
		if (!fr.ok) return null;
		var pack:NmaWorkingPack = {
			nma: built.nma,
			ctx: built.ctx,
			tapeSig: built.ctx.epoch.tapeKey,
			bars: bars
		};
		put(g, pack);
		return pack;
	}

	/**
	 * Build a child NMA genome by spine-replacing `slot`/`path` with `repl`, sharing siblings with
	 * `parent`. Registers under `childG`'s structural key when params are compatible (same length).
	 * Returns the child pack, or null if skipped.
	 */
	public static function spliceAndRegister(
		parent:NmaWorkingPack,
		slot:Int,
		path:GPath,
		repl:BoolNode,
		childG:StrategyGenome
	):Null<NmaWorkingPack> {
		if (Fitness.nmaWorking == null) return null;
		if (GenomeFeatures.boolIsSimCoupled(repl)) return null;
		if (!paramsMatchContext(childG, parent.ctx)) return null;
		var nmaRepl = NmaBijection.boolFromEnum(repl);
		var oldRoot = NmaSurgery.boolRoot(parent.nma, slot);
		var newRoot = NmaSurgery.replaceBool(oldRoot, path, nmaRepl);
		var childNma:NmaGenome = {
			entryLong: slot == 0 ? newRoot : parent.nma.entryLong,
			entryShort: slot == 1 ? newRoot : parent.nma.entryShort,
			exitLong: slot == 2 ? newRoot : parent.nma.exitLong,
			exitShort: slot == 3 ? newRoot : parent.nma.exitShort,
			size: parent.nma.size,
			params: childG.params,
			name: childG.name != null ? childG.name : parent.nma.name,
			lineage: childG.lineage,
			seedOrigin: childG.seedOrigin
		};
		// Fail closed if path surgery + any enum-side normalization (notably compactParams)
		// produced a different logical child. A stale-but-well-formed pack is worse than a miss.
		if (Canonical.structuralKey(NmaBijection.genomeToEnum(childNma))
			!= Canonical.structuralKey(childG)) return null;
		var pack:NmaWorkingPack = {
			nma: childNma,
			ctx: parent.ctx,
			tapeSig: parent.tapeSig,
			bars: parent.bars
		};
		put(childG, pack);
		return pack;
	}

	static function paramsMatchContext(g:StrategyGenome, ctx:NmaEvalContext):Bool {
		if (g.params.length != ctx.params.length) return false;
		for (i in 0...g.params.length)
			if (g.params[i].defaultValue != ctx.params[i]) return false;
		return true;
	}
}
