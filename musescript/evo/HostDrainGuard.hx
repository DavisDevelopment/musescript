package musescript.evo;

/**
 * Bucket F4 — live reinject / drain telemetry helpers.
 *
 * CorpusEvoRun reinjects host genomes when `hostAlive == 0` after elite shrink. After the
 * compactParams / Simplify / RivalryArena / NmaSemanticRdo projection-preservation fixes, a host
 * seed dragged through blind mutate + simplify must almost never lose its projections — reinject
 * events should stay ≈0 under normal variation.
 */
class HostDrainGuard {
	/** Live counter bumped by CorpusEvoRun when reinject fires (tests may reset). */
	public static var reinjectEvents:Int = 0;

	/** Genomes with at least one live host-projection reference (same predicate as CorpusEvoRun). */
	public static function countHostAlive(pop:Array<StrategyGenome>):Int {
		var n = 0;
		for (g in pop) {
			if (g == null) continue;
			if (ProjectionProvider.hostProjRefs(g).length > 0) n++;
		}
		return n;
	}

	/** True when CorpusEvoRun would attempt `[ew-host] reinject`. */
	public static inline function reinjectNeeded(pop:Array<StrategyGenome>):Bool
		return countHostAlive(pop) == 0;

	/**
	 * Fraction of mutate+simplify rounds that drop the projections *decl* (PSHost field).
	 * Severing an SProj read is allowed exploration; losing the decl is the drain bug.
	 * Acceptance: ≈0 after F1/F4 struct-rebuild fixes.
	 */
	public static function drainRateAfterMutations(
		seed:StrategyGenome, rounds:Int, rngSeed:Int = 1
	):Float {
		if (rounds <= 0) return 0.0;
		var v = new Variation(rngSeed);
		var drained = 0;
		var g = seed;
		for (_ in 0...rounds) {
			g = v.pointMutate(g);
			g = Simplify.simplifyGenome(g, v);
			if (!hasHostDecl(g)) {
				drained++;
				g = seed; // re-seed so subsequent rounds still stress the path
			}
		}
		return drained / (rounds + 0.0);
	}

	static function hasHostDecl(g:StrategyGenome):Bool {
		if (g.projections == null || g.projections.length == 0) return false;
		for (p in g.projections) {
			switch (p.sampler) {
				case PSHost(_): return true;
				default:
			}
		}
		return false;
	}
}
