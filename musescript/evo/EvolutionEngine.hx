package musescript.evo;

/**
 * Population lifecycle, tournament selection, and elitism.
 * Production deployments may swap this for Jenetics Engine via `jenetics.Externs`
 * while keeping Variation + Fitness in Haxe.
 */
class EvolutionEngine {
	public var popSize:Int;
	public var elite:Int;
	public var tournament:Int;
	var variation:Variation;
	/**
	 * Three INDEPENDENT streams, not one shared `rng` -- see RngStreams.hx's doc comment for the
	 * real confound this fixes (the P1 `--attr-cross-prob`/`--donor-cap` A/B: changing how often
	 * the crossover-choice roll passed shifted how many draws it consumed, which shifted every
	 * tournament pick for the rest of the run). Each of these three is an independently-toggleable
	 * decision axis (tournament selection; "attributed vs blind crossover"; "mutate or not"), so
	 * each gets its own seed -- enabling/reconfiguring one can never perturb another's sequence.
	 */
	var selectionRng:Rand;
	var crossoverChoiceRng:Rand;
	var mutateChoiceRng:Rand;
	/** ES-nudge's own pair (see `step`'s `esNudgeProb` doc comment): `esChoiceRng` decides WHETHER
	 * a child takes the ES path at all, `esRng` drives `Variation.esNudgeParam` itself -- both
	 * dedicated streams so `--es-nudge-prob` can be turned on/off/reconfigured without perturbing
	 * `selectionRng`'s tournament-pick sequence (drawn unconditionally either way, see below). */
	var esChoiceRng:Rand;
	var esRng:Rand;

	/**
	 * Stagnation tracking for adaptive mutation pressure (see step()'s mutateProb ramp below).
	 * Persisted across step() calls -- this is exactly the state a long corpus-evo run needs to
	 * notice "the population hasn't produced a new best in N generations" and respond, which a
	 * fixed 0.3 mutation-after-crossover rate structurally can't: once elitism + a converged
	 * population means crossover keeps re-combining near-identical parents, a FIXED rate applies
	 * the same weak pressure whether the population is thriving or completely stuck.
	 */
	var lastBest:Float = Fitness.NEG_INF;
	public var stagnantGens(default, null):Int = 0;
	/** Read-only mirror of step()'s own mutateProb formula, for tests/telemetry -- kept as a
	 * single source of truth (step() calls this, not a duplicated inline expression). */
	public function currentMutateProb():Float return Math.min(0.85, 0.3 + stagnantGens * 0.05);

	/** Reset stagnation tracking to a clean baseline -- for a caller (CorpusEvoRun's `--schedule`)
	 * that alternates between fitness functions on fundamentally different scales (a real-tape
	 * sharpe vs a `--compete` cohort z-score): comparing `genBest` across a mode SWITCH would read
	 * as either a spurious huge "improvement" or a spurious huge "regression" purely from the
	 * scale change, corrupting the adaptive mutation-pressure ramp with a signal that has nothing
	 * to do with real progress. Call this at every schedule transition. */
	public function resetStagnation():Void {
		lastBest = Fitness.NEG_INF;
		stagnantGens = 0;
	}

	/** Read-only handle to the underlying Variation's tuner, so a caller (CorpusEvoRun) can print
	 * an end-of-run summary of the learned growth weights without needing its own reference threaded
	 * through separately. */
	public var tuner(get, never):GrowthWeights;
	function get_tuner():GrowthWeights return variation.tuner;

	public function new(seed:Int, ?popSize:Int = 8, ?elite:Int = 2, ?tournament:Int = 3, ?indicatorPool:Array<String>, ?tuner:GrowthWeights) {
		this.popSize = popSize;
		this.elite = elite;
		this.tournament = tournament;
		this.variation = new Variation(seed, indicatorPool, tuner);
		this.selectionRng = RngStreams.stream(seed, RngStreams.SELECTION);
		this.crossoverChoiceRng = RngStreams.stream(seed, RngStreams.CROSSOVER_CHOICE);
		this.mutateChoiceRng = RngStreams.stream(seed, RngStreams.MUTATE_CHOICE);
		this.esChoiceRng = RngStreams.stream(seed, RngStreams.ES_CHOICE);
		this.esRng = RngStreams.stream(seed, RngStreams.ES_NUDGE);
	}

	public function seedPopulation(depth:Int = 3):Array<StrategyGenome> {
		return [for (_ in 0...popSize) variation.randomGenome(depth)];
	}

	/**
	 * `evalFn`, when supplied, is a real fitness oracle (genome -> score, same scale as
	 * `fitness`) used ONLY to drive `Variation.attributedPointMutate`'s node-ablation targeting
	 * -- see that function's doc comment. Omit it (default) for the exact prior behavior
	 * (uniform-random mutation site, no extra evaluations) -- every existing caller is
	 * unaffected unless it opts in.
	 *
	 * `attrCrossProb` (default 1.0 -- exact prior behavior: attributed crossover EVERY time
	 * `evalFn` is given) gates HOW OFTEN a child uses attribution-guided crossover vs blind
	 * `subtreeCrossover`. `attributedSubtreeCrossover`'s own doc comment already documents that
	 * a full attribution pass costs O(bool sites + donorSampleCap) oracle calls PER CHILD; even
	 * with `Fitness`'s structural-key compile-cache (see PLAN_EVO_SPEED.md) that's still real
	 * per-call overhead (fresh harness/interp/backtest) on every non-elite child, every
	 * generation. Lowering this below 1.0 trades some of that for cheap blind crossover -- which
	 * doubles as EXTRA exploration pressure (attribution concentrates search around what already
	 * looks good; blind crossover doesn't), the same "some randomness kept on purpose" reasoning
	 * `attributedPointMutate`'s own 20% uniform-fallback already relies on.
	 *
	 * `donorCap` (default 6, matching `attributedSubtreeCrossover`'s own default) threads through
	 * to bound how many donor candidates get oracle-scored per attributed crossover call.
	 *
	 * `esNudgeProb` (default `0.0` -- exact prior behavior, this path never taken) gates a THIRD
	 * offspring-production path alongside crossover+mutation: `Variation.esNudgeParam`, a (1+1)-ES
	 * local tune of one of `p1`'s existing numeric params (see that function's doc comment) instead
	 * of ordinary crossover/mutation. Only reachable when `evalFn` is supplied (needs a real oracle
	 * to accept/reject the nudge) AND `p1` actually has params to nudge (`esNudgeParam` is a no-op
	 * otherwise, so an empty-params genome silently falls through to ordinary crossover+mutation
	 * instead of wasting a turn). `p2`/`tournamentSelect` are still drawn UNCONDITIONALLY either
	 * way -- see `selectionRng`'s doc comment for why that matters.
	 */
	public function step(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>,
		?evalFn:StrategyGenome->Float,
		?attrCrossProb:Float = 1.0,
		?donorCap:Int = 6,
		?esNudgeProb:Float = 0.0
	):Array<StrategyGenome> {
		// Parsimony tiebreak (smaller node count wins a fitness tie) — matches musegene/
		// evolve.py's `scored.sort(key=lambda t: (t[0], -node_count(t[1])), reverse=True)`
		// exactly. Kept as a genuine TIEBREAK in the comparator, not folded into the fitness
		// value itself (see Fitness.score's doc comment for why that's the wrong place for it).
		var ranked = [for (i in 0...pop.length) { g: pop[i], f: fitness[i], n: Canonical.nodeCount(pop[i]) }];
		ranked.sort(function(a, b) {
			if (a.f != b.f) return a.f < b.f ? 1 : -1;
			return a.n < b.n ? -1 : a.n > b.n ? 1 : 0;
		});

		// Adaptive mutation pressure: ramp mutateProb up the longer the population goes without
		// a genuine improvement, back down to baseline the moment one lands. 0.3 -> 0.85 over
		// ~11 stagnant generations (0.05/gen), matching the kind of stall a fully-converged,
		// heavy-elitism population hits (see corpus-evo runs where `new=0` for many consecutive
		// generations -- crossover alone, on a homogeneous population, stops producing anything
		// actually new).
		var genBest = ranked.length > 0 ? ranked[0].f : Fitness.NEG_INF;
		if (genBest > lastBest + 1e-9) { lastBest = genBest; stagnantGens = 0; }
		else stagnantGens++;
		var mutateProb = currentMutateProb();

		var next:Array<StrategyGenome> = [];
		for (i in 0...Std.int(Math.min(elite, ranked.length)))
			next.push(ranked[i].g);
		while (next.length < popSize) {
			var p1 = tournamentSelect(ranked);
			var p2 = tournamentSelect(ranked);
			var child:StrategyGenome;
			if (evalFn != null && esNudgeProb > 0 && p1.params.length > 0 && esChoiceRng.float() < esNudgeProb) {
				child = variation.esNudgeParam(p1, evalFn, esRng);
			} else {
				// Attribution-guided crossover (see Variation.attributedSubtreeCrossover) whenever a
				// real fitness oracle is available AND the attrCrossProb roll passes -- same opt-in
				// contract as mutation just below: omitting evalFn (or rolling above attrCrossProb)
				// preserves the exact prior blind-crossover behavior.
				child = (evalFn != null && crossoverChoiceRng.float() < attrCrossProb)
					? variation.attributedSubtreeCrossover(p1, p2, evalFn, donorCap)
					: variation.crossover(p1, p2);
				if (mutateChoiceRng.float() < mutateProb) {
					child = evalFn != null ? variation.attributedPointMutate(child, evalFn) : variation.mutate(child);
				}
			}
			// Semantic-equivalence-aware simplification (see Simplify.hx): a pure, zero-eval-cost
			// tree rewrite -- collapses tautological/redundant subtrees crossover and mutation can
			// genuinely produce (x && (1>0), a op a duplicates, !!x, ...) to their equivalent
			// smaller form. Applied unconditionally (no evalFn needed, nothing to opt into) since
			// it never changes what a genome DOES, only how large its dead weight is.
			next.push(Simplify.simplifyGenome(child, variation));
		}
		return next;
	}

	function tournamentSelect(ranked:Array<{g:StrategyGenome, f:Float}>):StrategyGenome {
		var best = ranked[selectionRng.int(ranked.length)];
		for (_ in 1...tournament) {
			var cand = ranked[selectionRng.int(ranked.length)];
			if (cand.f > best.f) best = cand;
		}
		return best.g;
	}
}
