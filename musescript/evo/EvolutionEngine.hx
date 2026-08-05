package musescript.evo;

/**
 * Population lifecycle, tournament selection, and elitism.
 * Production deployments may swap this for Jenetics Engine via `jenetics.Externs`
 * while keeping Variation + Fitness in Haxe.
 */
class EvolutionEngine {
	/**
	 * Hard node budget after simplify (`--max-nodes`). Oversized children (blind grow under a
	 * thinned `--attr-cross-prob`) are discarded in favour of the recipient parent — stops the
	 * scoreMs 20→80 silent regressor when attribution no longer prunes bloat every child.
	 * 0 = uncapped. Default 40 (2× soft parsimony threshold).
	 */
	public static var maxNodes:Int = 40;
	/**
	 * Island size for the minimal archipelago substrate (`--deme-size`). 0 = single panmictic
	 * population (exact prior). When `> 0` and the pop is at least 2 demes, each island runs its
	 * own tournament + child production with an independent Variation memo — AttrPool fans out
	 * across demes (children stay serial inside a deme because workers are nested). Cuts shared
	 * `memoLock` traffic that limited `step.xo` parallel efficiency at pop=1000.
	 */
	public static var demeSize:Int = 0;
	/** Swap this many non-elite slots between adjacent demes every `migrateEvery` steps. */
	public static var migrateCount:Int = 2;
	/** Generations between ring-migration pulses. 0 = never migrate. */
	public static var migrateEvery:Int = 4;

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
	var migrateRng:Rand;
	/** Clone-vs-vary (`--clone-prob`); only drawn when cloneProb > 0. */
	var cloneChoiceRng:Rand;
	var demeSteps:Int = 0;

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

	public function new(seed:Int, ?popSize:Int = 8, ?elite:Int = 2, ?tournament:Int = 3, ?indicatorPool:Array<String>, ?tuner:GrowthWeights, ?fieldPool:Array<String>) {
		this.popSize = popSize;
		this.elite = elite;
		this.tournament = tournament;
		this.variation = new Variation(seed, indicatorPool, tuner, fieldPool);
		this.selectionRng = RngStreams.stream(seed, RngStreams.SELECTION);
		this.crossoverChoiceRng = RngStreams.stream(seed, RngStreams.CROSSOVER_CHOICE);
		this.mutateChoiceRng = RngStreams.stream(seed, RngStreams.MUTATE_CHOICE);
		this.esChoiceRng = RngStreams.stream(seed, RngStreams.ES_CHOICE);
		this.esRng = RngStreams.stream(seed, RngStreams.ES_NUDGE);
		this.lexicaseRng = RngStreams.stream(seed, RngStreams.LEXICASE);
		this.migrateRng = RngStreams.stream(seed, RngStreams.DEME_MIGRATE);
		this.cloneChoiceRng = RngStreams.stream(seed, RngStreams.CLONE_CHOICE);
	}

	/** Gate fund/aux series into genome growth from a tape's `Bar.data` (OHLCV-only when absent). */
	public function configureForTape(bars:Array<musescript.harness.Bar>):Void {
		variation.configureForTape(bars);
	}

	/** Gate fixed-universe symbols so Variation can grow `SPanel` → Expand `*_of("SYM",…)`
	 * and constrained `PanelAction` templates → HostABI `buy`/`rebalance_equal`/`target_weight`
	 * (plus closed rank→bags when `configureForPd` opens `xs_rank`).
	 * Does not attach a panel tape — pair with `configureForPanel` (or `Fitness.configurePanel`)
	 * so `PanelAction` genomes are scored via portfolio `runPanelBacktest`. */
	public function configureForUniverse(?syms:Array<String>):Void {
		variation.configureForUniverse(syms);
	}

	/**
	 * Gate closed NP palette (`KNp` → Expand `np_*`). Pass `null` for full catalog;
	 * `[]` clears. Default off — single-name genomes unchanged.
	 */
	public function configureForNp(?ops:Array<String>):Void {
		variation.configureForNp(ops);
	}

	/**
	 * Gate closed PD palette (`KPd` → Expand `pd_rank1d` / frame `pd_xs_rank` /
	 * size-safe `pd_shift` / closed rank→bag `PanelAction`s). Needs universe for
	 * xs_rank (shift does not). Pair xs_rank with `configureForPanel` so genomes
	 * score via `runPanelBacktest`. Pass `null` for full catalog; `[]` clears.
	 * Columnar NMA hosts `KPd("shift")` (lookback); `xs_rank` stays Expand panel.
	 * Frame PD stays WASM U; packed `pd_rank1d` may claim N ≤64; bags → host_eval.
	 */
	public function configureForPd(?ops:Array<String>):Void {
		variation.configureForPd(ops);
	}

	/**
	 * Attach a multi-symbol panel tape for fitness and gate Variation growth to its symbols.
	 * Composes with `configureForTape` (aux field pool stays independent). Pass `null` to
	 * clear the fitness panel only (universe growth tags are left as last configured).
	 */
	public function configureForPanel(?panel:musescript.harness.PanelFeed):Void {
		Fitness.configurePanel(panel);
		if (panel != null) variation.configureForUniverse(panel.symbols);
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
	 * `attrCrossProb` (default 1.0 -- attributed operators EVERY time `evalFn` is given) gates
	 * HOW OFTEN a child pays for attribution at all. On a hit: attributed crossover (± blind
	 * point-mutate). On a miss: blind mutate + blind crossover — never `attributedPointMutate`,
	 * or the flag would only relocate the oracle tax (see `produceChild`). Lowering below 1.0
	 * is a real throughput lever and also adds exploration pressure (attribution concentrates
	 * search around what already looks good).
	 *
	 * `donorCap` (default 2) threads through to bound how many donor candidates get considered
	 * per attributed crossover call. Under `--credit-cuts` (default with `--nma`) donors are
	 * bank-ranked with zero splice evals, so the cap mainly bounds Fisher–Yates work.
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
	 * `cloneProb` (default 0): with this probability a non-elite child is an exact copy of
	 * tournament-picked `p1` (no crossover/mutate). Cuts structural-unique churn — the measured
	 * ~850–970 uniques/gen floor under `--nma` — without changing fitness scoring. Dedicated
	 * `CLONE_CHOICE` stream; rolls only when `cloneProb > 0` so default stays bit-identical.
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
		?donorCap:Int = 2,
		?esNudgeProb:Float = 0.0,
		?caseFitness:Array<Array<Float>> = null,
		?cloneProb:Float = 0.0
	):Array<StrategyGenome> {
		var ds = demeSize;
		if (ds > 0 && pop.length >= ds * 2)
			return stepDemes(pop, fitness, evalFn, attrCrossProb, donorCap, esNudgeProb, caseFitness, ds, cloneProb);
		return stepOne(pop, fitness, evalFn, attrCrossProb, donorCap, esNudgeProb, caseFitness, cloneProb);
	}

	function stepOne(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>,
		evalFn:Null<StrategyGenome->Float>,
		attrCrossProb:Float,
		donorCap:Int,
		esNudgeProb:Float,
		caseFitness:Null<Array<Array<Float>>>,
		cloneProb:Float
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
			if (cloneProb > 0 && cloneChoiceRng.float() < cloneProb) {
				plans.push({p1: p1, p2: p2, esNudge: false, attrCross: false, doMutate: false, clone: true, slot: esPlans.length + plans.length});
			} else if (evalFn != null && esNudgeProb > 0 && p1.params.length > 0 && esChoiceRng.float() < esNudgeProb) {
				esPlans.push({p1: p1, p2: p2, esNudge: true, attrCross: false, doMutate: false, clone: false, slot: esPlans.length + plans.length});
			} else {
				var attrCross = evalFn != null && crossoverChoiceRng.float() < attrCrossProb;
				var doMutate = mutateChoiceRng.float() < mutateProb;
				plans.push({p1: p1, p2: p2, esNudge: false, attrCross: attrCross, doMutate: doMutate, clone: false, slot: esPlans.length + plans.length});
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
	 * Minimal archipelago: contiguous index islands of `ds`, local tournament, deme-parallel
	 * child production with independent Variation memos, ring migration every `migrateEvery`.
	 * Not Rivalry/Foundry — just the substrate that shrinks serial memo contention.
	 */
	function stepDemes(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>,
		evalFn:Null<StrategyGenome->Float>,
		attrCrossProb:Float,
		donorCap:Int,
		esNudgeProb:Float,
		caseFitness:Null<Array<Array<Float>>>,
		ds:Int,
		cloneProb:Float
	):Array<StrategyGenome> {
		var n = pop.length;
		var nDemes = Std.int(Math.ceil(n / ds));
		var globalBest = Fitness.NEG_INF;
		for (f in fitness) if (f > globalBest) globalBest = f;
		if (globalBest > lastBest + 1e-9) { lastBest = globalBest; stagnantGens = 0; }
		else stagnantGens++;
		var mutateProb = currentMutateProb();
		variation.beginGeneration();

		var timer = PhaseTimer.current;
		var tPlan = timer != null ? timer.start() : 0.0;
		var demeElites:Array<Array<StrategyGenome>> = [];
		var demePlans:Array<Array<ChildPlan>> = [];
		var demeEs:Array<Array<ChildPlan>> = [];
		var demeLens:Array<Int> = [];
		var slotBase = 0;
		for (d in 0...nDemes) {
			var lo = d * ds;
			var hi = Std.int(Math.min(n, lo + ds));
			var len = hi - lo;
			demeLens.push(len);
			var useLex = caseFitness != null && caseFitness.length == pop.length;
			var ranked = [for (i in lo...hi) {
				g: pop[i], f: fitness[i], n: Canonical.nodeCount(pop[i]), i: i
			}];
			ranked.sort(function(a, b) {
				if (a.f != b.f) return a.f < b.f ? 1 : -1;
				return a.n < b.n ? -1 : a.n > b.n ? 1 : 0;
			});
			var localElite = Std.int(Math.max(1, Math.round(elite * len / popSize)));
			if (localElite > ranked.length) localElite = ranked.length;
			var elites = [for (i in 0...localElite) ranked[i].g];
			demeElites.push(elites);
			var plans:Array<ChildPlan> = [];
			var esPlans:Array<ChildPlan> = [];
			while (elites.length + plans.length + esPlans.length < len) {
				var p1 = useLex ? lexicaseSelect(ranked, caseFitness) : tournamentSelect(ranked);
				var p2 = useLex ? lexicaseSelect(ranked, caseFitness) : tournamentSelect(ranked);
				if (cloneProb > 0 && cloneChoiceRng.float() < cloneProb) {
					plans.push({p1: p1, p2: p2, esNudge: false, attrCross: false, doMutate: false, clone: true, slot: slotBase + esPlans.length + plans.length});
				} else if (evalFn != null && esNudgeProb > 0 && p1.params.length > 0 && esChoiceRng.float() < esNudgeProb) {
					esPlans.push({p1: p1, p2: p2, esNudge: true, attrCross: false, doMutate: false, clone: false, slot: slotBase + esPlans.length + plans.length});
				} else {
					var attrCross = evalFn != null && crossoverChoiceRng.float() < attrCrossProb;
					var doMutate = mutateChoiceRng.float() < mutateProb;
					plans.push({p1: p1, p2: p2, esNudge: false, attrCross: attrCross, doMutate: doMutate, clone: false, slot: slotBase + esPlans.length + plans.length});
				}
			}
			demePlans.push(plans);
			demeEs.push(esPlans);
			slotBase += len;
		}
		if (timer != null) timer.stop(PhaseTimer.STEP_PLAN, tPlan);

		var pool = AttrPool.current;
		var demeNext:Array<Array<StrategyGenome>>;
		if (pool != null && pool.workers > 1 && nDemes > 1) {
			demeNext = pool.parallelIndexMap(nDemes, function(d:Int):Array<StrategyGenome> {
				return finishDeme(d, demeElites[d], demeEs[d], demePlans[d], variation.forkDeme(d), evalFn, donorCap);
			});
		} else {
			demeNext = [for (d in 0...nDemes)
				finishDeme(d, demeElites[d], demeEs[d], demePlans[d], variation, evalFn, donorCap)];
		}

		var next:Array<StrategyGenome> = [];
		for (chunk in demeNext) for (g in chunk) next.push(g);
		while (next.length < popSize && pop.length > 0) next.push(pop[next.length % pop.length]);
		if (next.length > popSize) next = next.slice(0, popSize);

		demeSteps++;
		if (migrateEvery > 0 && migrateCount > 0 && demeSteps % migrateEvery == 0 && nDemes > 1)
			ringMigrate(next, demeLens, migrateCount);
		return next;
	}

	function finishDeme(
		_d:Int,
		elites:Array<StrategyGenome>,
		esPlans:Array<ChildPlan>,
		plans:Array<ChildPlan>,
		v:Variation,
		evalFn:Null<StrategyGenome->Float>,
		donorCap:Int
	):Array<StrategyGenome> {
		var next = elites.copy();
		for (p in esPlans) next.push(produceChild(p, v, evalFn, donorCap));
		for (p in plans) next.push(produceChild(p, v, evalFn, donorCap));
		return next;
	}

	/** Ring-swap `count` random non-elite individuals between adjacent demes. */
	function ringMigrate(pop:Array<StrategyGenome>, demeLens:Array<Int>, count:Int):Void {
		var offsets = new Array<Int>();
		var acc = 0;
		for (len in demeLens) { offsets.push(acc); acc += len; }
		for (d in 0...demeLens.length) {
			var len = demeLens[d];
			var lo = offsets[d];
			var localElite = Std.int(Math.max(1, Math.round(elite * len / popSize)));
			if (localElite >= len) continue;
			var nd = (d + 1) % demeLens.length;
			var len2 = demeLens[nd];
			var lo2 = offsets[nd];
			var localElite2 = Std.int(Math.max(1, Math.round(elite * len2 / popSize)));
			if (localElite2 >= len2) continue;
			var swaps = Std.int(Math.min(count, Math.min(len - localElite, len2 - localElite2)));
			for (_ in 0...swaps) {
				var i = lo + localElite + migrateRng.int(len - localElite);
				var j = lo2 + localElite2 + migrateRng.int(len2 - localElite2);
				var tmp = pop[i];
				pop[i] = pop[j];
				pop[j] = tmp;
			}
		}
	}

	/**
	 * Produce one child from a Phase-A plan.
	 *
	 * Attribution is gated solely by `plan.attrCross` (`--attr-cross-prob`). Organ order when it
	 * fires: attributed XO, then optional blind `pointMutate` (XO already ranked sites/donors —
	 * a second attributed mutate on the cold child was pure tax). When the coin misses, both
	 * crossover and mutate are blind: the previous shape called `attributedPointMutate` on the
	 * miss path, so lowering `--attr-cross-prob` only relocated the oracle into `step.mut`
	 * (measured at pop=1000/`--nma`: prob 0 was slower than 1.0).
	 *
	 * «σπλάγχνα τάξον· δρόμος ἕπεται.»
	 */
	function produceChild(
		plan:ChildPlan,
		v:Variation,
		evalFn:Null<StrategyGenome->Float>,
		donorCap:Int
	):StrategyGenome {
		if (plan.clone) return plan.p1;
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
			// Blind mutate + blind XO: `--attr-cross-prob` is the only attribution gate.
			var p1 = plan.p1;
			var tMut = timer != null ? timer.start() : 0.0;
			p1 = v.mutate(p1);
			if (timer != null) timer.stop(PhaseTimer.STEP_MUT, tMut);
			var tXo = timer != null ? timer.start() : 0.0;
			child = v.crossover(p1, plan.p2);
			if (timer != null) timer.stop(PhaseTimer.STEP_XO, tXo);
		} else {
			var tXo = timer != null ? timer.start() : 0.0;
			child = v.crossover(plan.p1, plan.p2);
			if (timer != null) timer.stop(PhaseTimer.STEP_XO, tXo);
		}
		var maxN = maxNodes;
		// Hopeless bloat: skip simplify (step.simp) and keep the recipient — measured wall when
		// blind variation exploded under attr-cross 0.5 was dominated by scoring fat genomes.
		if (maxN > 0 && Canonical.nodeCount(child) > maxN * 2) return plan.p1;
		var tSimp = timer != null ? timer.start() : 0.0;
		// Compound-free genomes: simplifyBool is a pure walk — skip when every slot is terminal.
		var out = Simplify.hasCompoundBool(child)
			? Simplify.simplifyGenome(child, v)
			: child;
		if (timer != null) timer.stop(PhaseTimer.STEP_SIMP, tSimp);
		if (maxN > 0 && Canonical.nodeCount(out) > maxN) return plan.p1;
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

	/**
	 * Median absolute deviation of `xs` — RAW (population) MAD, i.e. NOT scaled by the 1.4826
	 * consistency constant that would make it a σ-estimate for normal data. That is deliberate:
	 * ε-lexicase uses this as a relative dispersion threshold on each case's scores, not as a
	 * standard deviation, so the unscaled statistic is the intended one. Returns 0 when empty.
	 *
	 * Delegates both medians to `StatsBuiltins.median`. It previously took
	 * `sorted[Std.int(len / 2)]` — the UPPER of the two central values for even-length input,
	 * rather than their mean — which put a small systematic upward bias into the ε threshold
	 * and meant the codebase carried two different definitions of "median", with the less
	 * correct one sitting in the selection path.
	 */
	static function mad(xs:Array<Float>):Float {
		if (xs.length == 0) return 0.0;
		var med = musescript.builtins.StatsBuiltins.median(xs);
		return musescript.builtins.StatsBuiltins.median([for (x in xs) Math.abs(x - med)]);
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
	public var clone:Bool;
	public var slot:Int;
}
