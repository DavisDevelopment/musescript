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
	/** ε-lexicase case-order stream (`--lexicase`); unused when `caseFitness` is null. */
	var lexicaseRng:Rand;

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
		this.lexicaseRng = RngStreams.stream(seed, RngStreams.LEXICASE);
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
	 *
	 * `caseFitness`, when non-null and aligned with `pop` (same length; each row a per-case score
	 * vector), replaces tournament parent picks with **ε-lexicase** (`--lexicase`). Aggregate
	 * `fitness` still drives elitism + stagnation; only who reproduces changes — same containment
	 * contract as speciation/novelty (selection-only).
	 */
	public function step(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>,
		?evalFn:StrategyGenome->Float,
		?attrCrossProb:Float = 1.0,
		?donorCap:Int = 6,
		?esNudgeProb:Float = 0.0,
		?caseFitness:Array<Array<Float>> = null
	):Array<StrategyGenome> {
		// Parsimony tiebreak (smaller node count wins a fitness tie) — matches musegene/
		// evolve.py's `scored.sort(key=lambda t: (t[0], -node_count(t[1])), reverse=True)`
		// exactly. Kept as a genuine TIEBREAK in the comparator, not folded into the fitness
		// value itself (see Fitness.score's doc comment for why that's the wrong place for it).
		var useLex = caseFitness != null && caseFitness.length == pop.length;
		var ranked = [for (i in 0...pop.length) {
			g: pop[i], f: fitness[i], n: Canonical.nodeCount(pop[i]), i: i
		}];
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

		// P1.1: wipe per-parent ablation memo once per generation (see Variation.beginGeneration).
		variation.beginGeneration();

		var next:Array<StrategyGenome> = [];
		for (i in 0...Std.int(Math.min(elite, ranked.length)))
			next.push(ranked[i].g);

		// Phase A — serial planning. Every selection / crossover-choice / mutate-choice /
		// es-choice draw happens here, in the same order as the old interleaved loop, so those
		// three RngStreams stay bit-identical under `--seed` whether or not AttrPool parallelizes
		// Phase B. Variation-internal draws move to per-slot streams (VARIATION_PARALLEL).
		var timer = PhaseTimer.current;
		var tPlan = timer != null ? timer.start() : 0.0;
		var plans:Array<ChildPlan> = [];
		var esPlans:Array<ChildPlan> = [];
		while (next.length + plans.length + esPlans.length < popSize) {
			var p1 = useLex ? lexicaseSelect(ranked, caseFitness) : tournamentSelect(ranked);
			var p2 = useLex ? lexicaseSelect(ranked, caseFitness) : tournamentSelect(ranked);
			if (evalFn != null && esNudgeProb > 0 && p1.params.length > 0 && esChoiceRng.float() < esNudgeProb) {
				esPlans.push({p1: p1, p2: p2, esNudge: true, attrCross: false, doMutate: false, slot: esPlans.length + plans.length});
			} else {
				var attrCross = evalFn != null && crossoverChoiceRng.float() < attrCrossProb;
				var doMutate = mutateChoiceRng.float() < mutateProb;
				plans.push({p1: p1, p2: p2, esNudge: false, attrCross: attrCross, doMutate: doMutate, slot: esPlans.length + plans.length});
			}
		}
		if (timer != null) timer.stop(PhaseTimer.STEP_PLAN, tPlan);

		// ES-nudge uses the shared `esRng` stream — keep it serial so parallel workers cannot
		// race those draws. Rare path (`--es-nudge-prob` defaults off).
		for (p in esPlans) next.push(produceChild(p, variation, evalFn, donorCap));

		// Phase B — produce the ordinary children. With an AttrPool the bodies run concurrently;
		// each slot forks a Variation that shares the site-delta / donor-score memos + tuner.
		var pool = AttrPool.current;
		if (pool != null && pool.workers > 1 && plans.length > 1) {
			var children = pool.parallelIndexMap(plans.length, function(i:Int):StrategyGenome {
				return produceChild(plans[i], variation.forkForSlot(plans[i].slot), evalFn, donorCap);
			});
			for (c in children) next.push(c);
		} else {
			for (p in plans) next.push(produceChild(p, variation, evalFn, donorCap));
		}
		return next;
	}

	/**
	 * Produce one child from a Phase-A plan.
	 *
	 * Organ order (measured at pop=1000): attribution is the expensive gut. Paying it twice —
	 * attributed XO on a warm elite, then attributed mutate on the cold child — dominated
	 * `step.mut`. Rearrangement:
	 *  - attributed XO ± blind pointMutate when `attrCross` (XO already ranked sites/donors)
	 *  - attributed mutate on `p1` then blind XO when mutate-only (elites share site-delta memo)
	 *
	 * «σπλάγχνα τάξον· δρόμος ἕπεται.»
	 */
	function produceChild(
		plan:ChildPlan,
		v:Variation,
		evalFn:Null<StrategyGenome->Float>,
		donorCap:Int
	):StrategyGenome {
		var timer = PhaseTimer.current;
		var child:StrategyGenome;
		if (plan.esNudge) {
			child = v.esNudgeParam(plan.p1, evalFn, esRng);
		} else if (evalFn != null && plan.attrCross) {
			// Attribution lives in crossover; mutation is structural exploration only.
			var tXo = timer != null ? timer.start() : 0.0;
			child = v.attributedSubtreeCrossover(plan.p1, plan.p2, evalFn, donorCap);
			if (timer != null) timer.stop(PhaseTimer.STEP_XO, tXo);
			if (plan.doMutate) {
				var tMut = timer != null ? timer.start() : 0.0;
				child = v.pointMutate(child);
				if (timer != null) timer.stop(PhaseTimer.STEP_MUT, tMut);
			}
		} else if (plan.doMutate) {
			// Mutate the tournament parent first — site-delta memo hits across re-picks — then
			// blind-cross with p2. Attributed mutate-after-XO on a fresh child was pure cold tax.
			var p1 = plan.p1;
			var tMut = timer != null ? timer.start() : 0.0;
			p1 = evalFn != null ? v.attributedPointMutate(p1, evalFn) : v.mutate(p1);
			if (timer != null) timer.stop(PhaseTimer.STEP_MUT, tMut);
			var tXo = timer != null ? timer.start() : 0.0;
			child = v.crossover(p1, plan.p2);
			if (timer != null) timer.stop(PhaseTimer.STEP_XO, tXo);
		} else {
			var tXo = timer != null ? timer.start() : 0.0;
			child = v.crossover(plan.p1, plan.p2);
			if (timer != null) timer.stop(PhaseTimer.STEP_XO, tXo);
		}
		var tSimp = timer != null ? timer.start() : 0.0;
		var out = Simplify.simplifyGenome(child, v);
		if (timer != null) timer.stop(PhaseTimer.STEP_SIMP, tSimp);
		return out;
	}

	function tournamentSelect(ranked:Array<{g:StrategyGenome, f:Float, n:Int, i:Int}>):StrategyGenome {
		var best = ranked[selectionRng.int(ranked.length)];
		for (_ in 1...tournament) {
			var cand = ranked[selectionRng.int(ranked.length)];
			if (cand.f > best.f) best = cand;
		}
		return best.g;
	}

	/**
	 * Semi-dynamic ε-lexicase (La Cava et al. 2016): shuffle cases, filter the pool to individuals
	 * within ε of the best on each case (ε = MAD of remaining scores on that case), stop when one
	 * remains or cases are exhausted, then pick uniformly from the survivors.
	 */
	function lexicaseSelect(
		ranked:Array<{g:StrategyGenome, f:Float, n:Int, i:Int}>,
		cases:Array<Array<Float>>
	):StrategyGenome {
		var pool = ranked.copy();
		var nCases = 0;
		for (row in cases) if (row != null && row.length > nCases) nCases = row.length;
		if (nCases == 0 || pool.length == 0) return tournamentSelect(ranked);
		var order = [for (c in 0...nCases) c];
		for (i in 0...order.length - 1) {
			var j = i + lexicaseRng.int(order.length - i);
			var t = order[i]; order[i] = order[j]; order[j] = t;
		}
		for (c in order) {
			if (pool.length <= 1) break;
			var scores = new Array<Float>();
			for (ind in pool) {
				var row = cases[ind.i];
				var v = (row != null && c < row.length && !Math.isNaN(row[c])) ? row[c] : Fitness.NEG_INF;
				scores.push(v);
			}
			var best = Fitness.NEG_INF;
			for (s in scores) if (s > best) best = s;
			var eps = mad(scores);
			var nextPool = new Array<{g:StrategyGenome, f:Float, n:Int, i:Int}>();
			for (k in 0...pool.length) {
				if (scores[k] >= best - eps) nextPool.push(pool[k]);
			}
			if (nextPool.length > 0) pool = nextPool;
		}
		return pool[lexicaseRng.int(pool.length)].g;
	}

	/** Median absolute deviation of `xs` (population MAD); 0 when degenerate. */
	static function mad(xs:Array<Float>):Float {
		if (xs.length == 0) return 0.0;
		var sorted = xs.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var med = sorted[Std.int(sorted.length / 2)];
		var devs = [for (x in sorted) Math.abs(x - med)];
		devs.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return devs[Std.int(devs.length / 2)];
	}
}

/** One child's production plan, fixed during EvolutionEngine's serial Phase A. */
@:structInit
class ChildPlan {
	public var p1:StrategyGenome;
	public var p2:StrategyGenome;
	public var esNudge:Bool;
	public var attrCross:Bool;
	public var doMutate:Bool;
	public var slot:Int;
}
