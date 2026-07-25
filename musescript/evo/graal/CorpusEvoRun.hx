package musescript.evo.graal;

import musescript.evo.Canonical;
import musescript.evo.CorpusSeed;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.RegistryPalette;
import musescript.evo.Variation;
import musescript.evo.StrategyGenome;
import musescript.evo.BasketFitness;
import musescript.evo.SurrogateModel;
import musescript.evo.SymbolSelector;
import musescript.evo.graal.Polyglot;
import musescript.evo.graal.GraalWasmHost;
import musescript.evo.graal.EvoCache.CachedEval;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
// `--sim-tape` (see this session's MurmurationSim x corpus-evo integration plan): gated behind
// `-D kestrel`, same convention musescript.murmuration is imported under everywhere else (see
// GeneRunner.hx's `loadBars` -- "public build strips this and every use of them below; core
// never imports musescript.kestrel itself either way"). `build-corpus-evo.hxml` needs `-D
// kestrel` added for this import to resolve; a scratch build without it simply compiles this
// file with `--sim-tape` unavailable (`simTapeOn` stays false, throws if ever requested).
#if kestrel
import musescript.murmuration.MurmurationConfig;
import musescript.murmuration.MurmurationSim;
import musescript.murmuration.MurmurationTape;
#end
import musescript.parse.MuseParser;
import musescript.compile.ModuleExpand;
import musescript.compile.TemplateExpand;
import musescript.compile.SeriesLowering;
import musescript.compile.StrategyWasmEmitter;
import sys.thread.Thread;
import sys.thread.Deque;

typedef ModuleEntry = {var strings:Array<String>; var wasmPath:String;}
typedef EvalJob = {var key:String; var wasmPath:String; var strings:Array<String>; var stop:Bool;}
// `perSymbolSharpe` (parallel to the `--tapes` basket, one entry per symbol) -- ONLY needed for
// CorpusEvoRun's opt-in `--curriculum` (see this session's neuroevolution-inspired-upgrades plan):
// `BasketFitness.aggregateBasket` deliberately collapses per-symbol detail away inside the worker,
// so curriculum weighting (which needs "how is the population doing on EACH symbol this
// generation") requires the workers to also hand back the per-symbol numbers, not just the
// aggregate. Always populated (one Fitness/WASM run per symbol already happens regardless of
// `--curriculum`) -- cheap to carry, and every existing consumer of these typedefs just ignores
// the extra field.
typedef EvalResult = {var key:String; var trades:Int; var sharpe:Float; var finalEquity:Float; var avgHold:Float; var longFrac:Float; var perSymbolSharpe:Array<Float>;}
typedef FallbackJob = {var key:String; var useFullTape:Bool; var stop:Bool;}
typedef FallbackResult = {var key:String; var ok:Bool; var trades:Int; var sharpe:Float; var equity:Float; var fills:Null<Array<musescript.harness.Fill>>; var perSymbolSharpe:Array<Float>; var bankrupt:Bool;}

/**
 * Evolution run seeded with the ENTIRE reverse-compilable strategy corpus (the tournament
 * agents' hand-written strategies + one genome per compatible `ta` indicator, see
 * CorpusSeed.hx), fitness-evaluated on the real GraalWasm host (same compile-and-run pipeline
 * as EvoBench.hx, reused directly -- WAT emission via StrategyWasmEmitter, batched wat2wasm
 * assembly, a persistent multi-threaded GraalWasmHost worker pool with warm per-thread
 * instance caches).
 *
 * Generation 0 evaluates the FULL seeded population (however large the corpus makes it) so
 * every seed genuinely gets a fitness-ranked shot at survival; `--pop` caps how large
 * subsequent generations regrow to (elites + tournament-selected offspring), matching
 * EvolutionEngine's own step() semantics -- the corpus is a one-time diversity injection into
 * gen 0, not a population size the run keeps paying to re-evaluate every generation.
 *
 * Usage: CorpusEvoRun [--pop N] [--gens N] [--seed N] [--threads N] [--corpus DIR]
 */
class CorpusEvoRun {
	static var watDir = "build/graal/evo-corpus";

	static function main() {
		var pop = argInt("--pop", 64);
		var gens = argInt("--gens", 12);
		var seed = argInt("--seed", 42);
		var threads = argInt("--threads", Std.int(Math.max(1,
			java.lang.Runtime.getRuntime().availableProcessors() / 2)));
		var corpusDir = argStr("--corpus", "examples/strategy-tournament");
		var tapePath = argStr("--tape", null);
		// Multi-symbol basket mode (see this session's multi-symbol plan): `--tapes a.csv,b.csv,...`
		// evolves against a BASKET of symbols instead of one, with fitness aggregated across all of
		// them (see BasketFitness.aggregateBasket) -- opt-in, so a plain `--tape` run (or neither
		// flag, the `spy.csv`-default path) builds a one-element basket and is completely
		// unaffected. `--tapes`, when given, takes priority over `--tape`.
		var tapesArg = argStr("--tapes", null);
		var oosFrac = argFloat("--oos-frac", 0.25);
		var embargo = argInt("--embargo", 21);
		// Soft-cap parsimony: free below the threshold, `parsimonyLambda` sharpe per node past
		// it. See Fitness.score's doc comment. Threshold=20 is roughly "typical" genome size
		// observed across this run's own champions so far; tune both from the command line
		// rather than re-editing source to experiment.
		var parsimonyThreshold = argInt("--parsimony-threshold", 20);
		var parsimonyLambda = argFloat("--parsimony-lambda", 0.01);
		// Fitness memo (see EvoCache): on by default, `--no-cache` disables it (e.g. to force a
		// cold re-measure of eval throughput). Scoped to the IS tape signature so the on-disk
		// file only ever warm-starts a re-run on the identical bars.
		var noCache = argFlag("--no-cache");
		// Prefix triage (successive-halving gate) for the EXPENSIVE serial JS-fallback path only
		// -- the native-WASM path is already cheap and parallel, so triaging it would only add
		// prefix-eval overhead for no saving. A new fallback genome is first scored on a cheap
		// `triageBars`-length prefix; only the top `triageKeep` fraction earns a full-tape eval,
		// the rest are killed for the generation (NEG_INF, and NOT written to the full memo, so a
		// genome the prefix under-rates can still be promoted if it recurs via a cheaper backend).
		// `--triage-bars 0` disables it; -1 (default) auto-sizes to a fifth of the IS tape.
		var triageBars = argInt("--triage-bars", -1);
		var triageKeep = argFloat("--triage-keep", 0.5);
		// MAP-Elites diversity preservation (see MapElites.hx): on by default. `--no-map-elites`
		// disables both the archive bookkeeping and the immigrant injection below, restoring plain
		// raw-fitness-only selection for an A/B comparison. `--immigrant-rate` is the fraction of
		// EACH generation's non-elite slots eligible to be replaced by a distinct-cell archive
		// champion not already present in the population -- 0 disables injection while leaving the
		// archive itself running (so `--immigrant-rate 0` still reports the diversity summary).
		var mapElitesOn = !argFlag("--no-map-elites");
		var immigrantRate = argFloat("--immigrant-rate", 0.2);
		// Speciation / fitness-sharing (see Canonical.shapeSignature/shapeDistance): a STRUCTURAL
		// complement to MAP-Elites' BEHAVIORAL niching, adjusting SELECTION pressure only -- never
		// the reported champion or the archive, which both still read raw `fitness`. ON by
		// default now (a deliberate behavior change, per this session's explicit direction) --
		// this is one of the two existing anti-stagnation levers that were sitting unused while a
		// single lineage held the champion slot for 140+ generations in a real run; `--no-
		// speciation` restores the old off-by-default behavior.
		var speciationOn = !argFlag("--no-speciation");
		var speciationThreshold = argInt("--speciation-threshold", 4);
		var speciationLambda = argFloat("--speciation-lambda", 0.3);
		// Novelty bonus on top of the MAP-Elites archive (MapElites.noveltyDistance): rewards a
		// genome for landing FAR from anything already archived, not just for filling an empty
		// cell. NEW DEFAULT 0.1 (was 0.0/off) -- the other half of the same anti-stagnation fix
		// as `speciationOn` above; `--novelty-weight 0` restores the old no-effect behavior.
		var noveltyWeight = argFloat("--novelty-weight", 0.1);
		// ES-style (1+1) local param tuning (see Variation.esNudgeParam) -- a THIRD offspring path
		// alongside crossover/mutation in EvolutionEngine.step, gated by its own dedicated rng
		// streams (RngStreams.ES_CHOICE/ES_NUDGE). `0.0` (default) is exactly today's behavior.
		var esNudgeProb = argFloat("--es-nudge-prob", 0.0);
		// Adversarial curriculum weighting across the `--tapes` basket (see BasketFitness.
		// aggregateBasket's `weights` param): biases the basket-mean toward whichever symbols the
		// population is CURRENTLY worst at, recomputed every generation from that generation's own
		// per-symbol results. Off by default -- a plain uniform mean, identical to today's basket
		// aggregation. Meaningless (and harmless) on a single-`--tape` run: one symbol always gets
		// weight 1.0.
		var curriculumOn = argFlag("--curriculum");
		var curriculumTemp = argFloat("--curriculum-temp", 1.0);
		// Persist the MAP-Elites archive to disk at end of run -- one runnable .ms file per
		// occupied behavioral cell (see the save block near CORPUS_EVO_OK below). Off by default;
		// `--elites-dir` overrides the default output directory.
		var saveElites = argFlag("--save-elites");
		var elitesDir = argStr("--elites-dir", "build/graal/elites");
		// Online-learned structural fitness surrogate (see Canonical.shapeFeatures/
		// SurrogateModel.hx): an even-cheaper pre-filter ahead of the existing triage-prefix eval,
		// trained for free on every real evaluation this run already computes. Off by default --
		// zero backtests skipped, zero behavior change. `--surrogate-keep` (default 0.85, looser
		// than `--triage-keep`'s 0.5) is deliberately conservative: the model is coarse and still
		// warming up early in a run, so it should only ever cut the CLEAREST duds.
		var surrogateOn = argFlag("--surrogate");
		var surrogateKeep = argFloat("--surrogate-keep", 0.85);
		var surrogatePath = argStr("--surrogate-path", null);
		// Auto-tuned growth-node-type weights (see GrowthWeights.hx / Variation.attributedPointMutate's
		// reward call). On by default with in-memory-only learning; `--tuner-path` opts into disk
		// persistence (warm-started + saved at the end, same convention as EvoCache) so tuning
		// compounds across repeated runs on the same corpus instead of restarting from
		// GrowthWeights' literal defaults every time.
		var tunerOn = !argFlag("--no-tuner");
		var tunerPath = argStr("--tuner-path", null);
		// Transaction cost (see OrderSim.executeLong/executeShort/executeFlat's doc comment): every
		// genome traded for FREE until this existed -- Expand.hx renders `long(size)`/`short(size)`/
		// `flat()`, the legacy immediate-fill verbs, which never applied slippage before the OrderSim
		// fix landed alongside this flag. 20bps default matches this project's own established
		// "realistic cost" convention elsewhere (see synth/marketsim's walk-forward gates, e.g.
		// "S&P100 Sharpe +2.99@20bps"). `--cost-bps 0` restores the old free-trading behavior for an
		// A/B comparison.
		var costBps = argFloat("--cost-bps", 20);
		// `--sim-tape` (Phase 1 of the MurmurationSim x corpus-evo integration plan): evolve
		// against an ENDOGENOUS-price tape generated by MurmurationSim instead of a fixed
		// historical CSV -- gated behind `-D kestrel` (see the import block at the top of this
		// file). `--tapes`/`--tape` are ignored when this is set. `--sim-config` optionally
		// overrides MurmurationConfig defaults from a JSON file (same shape/convention as
		// GeneRunner.hx's `--murmuration-config`); `--sim-seed` defaults to `--seed` so a run is
		// still fully reproducible without a second seed to track. This is still PRICE-TAKING
		// (the sim runs once, up front, before any genome trades it) -- true competition (genomes
		// as agents moving the shared book) is Phase 2, not implemented here.
		var simTapeOn = argFlag("--sim-tape");
		var simSteps = argInt("--sim-steps", 3000);
		var simSeed = argInt("--sim-seed", seed);
		var simConfigPath = argStr("--sim-config", null);
		// Bankruptcy difficulty crank (see OrderSim.hx's `equityFloor`/`bankrupt` doc comment):
		// general-purpose, not sim-tape-specific -- a `--tape`/`--tapes` run can opt in too.
		// `--equity-floor 0` (default) is fully disabled, zero behavior change. A positive floor
		// FORCES every genome down the JS-fallback path (`forceFallback` below) -- the native-WASM
		// backend doesn't implement the kill-switch yet (it's a compiled-WAT execution engine, not
		// OrderSim.hx), so honoring the floor at all means giving up WASM's speed for the
		// interpreter's ability to check it. Documented tradeoff, not a silent gap: still
		// worker-pooled/parallel via the existing fbJobQueue pool, just the slower backend.
		var startCapital = argFloat("--start-capital", 100000);
		var equityFloor = argFloat("--equity-floor", 0.0);
		// Per-generation difficulty ramp (Phase 1's other half -- the actual "moving target" on
		// the solvency axis, vs. a single fixed capital/floor for the whole run). Off by default.
		// `startCapital` ramps LINEARLY down to `--difficulty-end-capital` and `equityFloor` ramps
		// UP to `--difficulty-end-floor` as `gen` advances from 0 to `gens-1` -- a genome that
		// stayed solvent on gen 0's generous terms can still bust out on gen 500's tighter ones,
		// so nothing can "solve" the account once and coast. Defaults (when the flag is on but the
		// end-values aren't overridden): capital HALVES by the end of the run, and the floor rises
		// to 25% of the ORIGINAL starting capital -- meaningful pressure without being a cliff.
		// CRITICAL correctness note: a memo'd eval (EvoCache) is only valid for the EXACT capital/
		// floor it was computed under, so every generation the ramp changes either value, `cache`/
		// `triageCache` get wiped (see EvoCache.clear()) -- a ramping run trades away cross-
		// generation caching entirely, since "yesterday's capital" is a genuinely different backtest
		// from today's, not a stale-but-still-valid one. Disk persistence is skipped too (`cache`/
		// `triageCache` are always constructed with a `null` path once this is on) for the same
		// reason a single run-level `bankruptSuffix` can't namespace a value that changes every gen.
		var difficultyScheduleOn = argFlag("--difficulty-schedule");
		var difficultyEndCapital = argFloat("--difficulty-end-capital", startCapital * 0.5);
		var difficultyEndFloor = argFloat("--difficulty-end-floor", startCapital * 0.25);
		// Robustness-adjusted real-tape fitness (see Fitness.robustScore's doc comment): splits
		// each genome's OWN equity curve into `--fitness-windows` segments and scores
		// mean-minus-`--fitness-window-lambda`*std across them instead of one whole-tape Sharpe --
		// a genome that's excellent in one stretch and mediocre elsewhere can no longer look
		// identical to one that's modestly good throughout. THE NEW DEFAULT (4 windows) -- a
		// deliberate behavior change, not an opt-in-off-by-default addition like most flags in
		// this file, per this session's own explicit direction. `--fitness-windows 1` (or 0)
		// restores today's exact single-window behavior. Same "no native-WASM support" story as
		// `--equity-floor` -- the compiled-WAT backend computes sharpe internally and never
		// exposes a per-bar equity curve, so this FORCES every genome down the JS-fallback path
		// too (see `forceFallback` below) -- a real, accepted speed-for-robustness tradeoff at the
		// new default, same one `--equity-floor` already made.
		var fitnessWindows = argInt("--fitness-windows", 4);
		var fitnessWindowLambda = argFloat("--fitness-window-lambda", 0.5);
		if (fitnessWindows > 1) Sys.println('ROBUSTNESS FITNESS: on -- $fitnessWindows windows, lambda=$fitnessWindowLambda (forces JS-fallback backend; --fitness-windows 1 restores plain whole-tape Sharpe)');
		var forceFallback = equityFloor > 0 || difficultyScheduleOn || fitnessWindows > 1;
		// `--compete` (Phase 2 of the MurmurationSim x corpus-evo integration plan):
		// "genome-in-the-loop" -- every UNIQUE genome this generation becomes an `Evolved` agent
		// (see MurmurationEmbedding.Archetype/GenomeStepper.hx) in ONE shared MurmurationSim run,
		// trading against each other AND a background population of hand-coded archetypes for the
		// SAME liquidity, so the price is something the cohort itself moves -- not a frozen tape.
		// Gated behind `-D kestrel`, same as `--sim-tape`. Completely REPLACES the WASM/fallback/
		// triage/surrogate/MAP-Elites eval-and-score block for the generation (see the `competeOn`
		// branch below) -- those all assume an independent per-genome backtest against a fixed
		// tape, which competitive co-evolution doesn't have. `--curriculum`/`--surrogate`/
		// `--save-elites` are silently inert when combined with `--compete` (documented, not
		// wired) -- a real follow-up, not this pass's scope.
		// Fitness = z-scored mark-to-market wealth within the cohort (`competeGenerationFitness`
		// below) -- invariant to a uniform wealth shift across the whole cohort (can't win by
		// everyone getting richer together), which is the plan's own stated design goal for
		// "relative, not absolute" competitive fitness.
		var competeFlag = argFlag("--compete");
		var competeAgents = argInt("--compete-agents", 500);
		// `--compete-symbols N` (Part A of the symbol-selection co-evolution plan): each
		// individual ALSO carries a co-evolved `SymbolSelector` (see that class's doc comment) --
		// a small linear scoring function over N candidate synthetic markets' own regime knobs,
		// picking which ONE market to enter this generation. `N=1` (the default) degenerates to
		// exactly today's single-market `--compete` behavior -- no selector, no market choice,
		// `competeGenerationFitness` runs unchanged. This is deliberately a SEPARATE, PARALLEL
		// population (`selectors` below), never a `StrategyGenome` field -- see the plan's own
		// reasoning for why (keeps Variation/EvolutionEngine/Canonical/Expand/CorpusSeed
		// completely untouched).
		var competeSymbols = argInt("--compete-symbols", 1);
		if (competeSymbols > 1) Sys.println('COMPETE multi-market: on -- $competeSymbols candidate synthetic markets/gen, each individual co-evolves a SymbolSelector to pick which ONE to enter');
		// `--schedule "real:R,compete:C"`: alternate fitness modes across the SAME run/population
		// instead of picking one for the whole run. Parses into a repeating cycle of
		// {isCompete, count} segments; `null` (the default, no flag) preserves today's exact
		// behavior -- `competeOn` stays pinned to `competeFlag` for the whole run, no schedule
		// logic ever runs. `scheduleModeForGen` picks THIS generation's mode via modulo over the
		// cycle's total length.
		var scheduleSegments:Array<{isCompete:Bool, count:Int}> = null;
		var scheduleArg = argStr("--schedule", null);
		if (scheduleArg != null) {
			scheduleSegments = [];
			for (part in scheduleArg.split(",")) {
				var kv = part.split(":");
				if (kv.length != 2) throw '--schedule: malformed segment "$part" -- expected "real:N" or "compete:N"';
				var mode = StringTools.trim(kv[0]).toLowerCase();
				var count = Std.parseInt(StringTools.trim(kv[1]));
				if (count == null || count < 1) throw '--schedule: segment "$part" needs a positive integer count';
				if (mode != "real" && mode != "compete") throw '--schedule: segment "$part" -- mode must be "real" or "compete"';
				scheduleSegments.push({isCompete: mode == "compete", count: count});
			}
		}
		var scheduleTotal = 0;
		if (scheduleSegments != null) for (s in scheduleSegments) scheduleTotal += s.count;
		function scheduleModeForGen(gen:Int):Bool {
			var pos = gen % scheduleTotal;
			for (s in scheduleSegments) {
				if (pos < s.count) return s.isCompete;
				pos -= s.count;
			}
			return scheduleSegments[scheduleSegments.length - 1].isCompete; // unreachable; satisfies return-path checking
		}
		// `competeRequested`: is compete infrastructure (MurmurationSim, GenomeStepper, the
		// kestrel requirement, the multi-market fitness function) needed AT ALL this run --
		// whether from a bare `--compete` OR because the schedule visits a "compete" segment at
		// some point. Drives the ONE-TIME startup checks below; per-generation `competeOn` (a
		// mutable var, reassigned at the top of the generation loop) drives the actual
		// eval-and-score branch each generation.
		var competeRequested = competeFlag || (scheduleSegments != null && Lambda.exists(scheduleSegments, s -> s.isCompete));
		var competeOn = scheduleSegments != null ? scheduleModeForGen(0) : competeFlag;
		if (scheduleSegments != null)
			Sys.println('SCHEDULE: on -- alternating ' + [for (s in scheduleSegments) '${s.isCompete ? "compete" : "real"}:${s.count}'].join(",")
				+ ' (cycle length $scheduleTotal gens); --compete-agents ${competeAgents}, ${simSteps} ticks/gen during compete segments');
		else if (competeFlag)
			Sys.println('COMPETE mode: on -- every unique genome/gen becomes an Evolved agent in one shared MurmurationSim (${competeAgents} total agents/run, ${simSteps} ticks/gen)'
				+ ' -- --curriculum/--surrogate/--save-elites are inert in this mode');
			// Rare "merger" crossover event (see this session's merger-crossover-event +
			// sequential-tape plan): once per generation, with probability `--merger-rate` (0 =
			// off, the default), draw the top `--merger-k` genomes from the MAP-Elites archive(s)
			// (split evenly across `archiveReal`/`archiveCompete` when both are populated -- the
			// "different generations and trading styles" hall-of-fame the user asked for, free
			// bookkeeping since a cell only changes occupant when strictly beaten), try every
			// pairwise recombination, keep the single best-scoring hybrid, then splice
			// `--merger-inject` mutated clones of it into the population's non-elite slots
			// (mirrors `injectArchiveDiversity`'s own slot-selection pattern below, just with a
			// freshly-bred "super-genome" as the source instead of an existing archive occupant).
			var mergerRate = argFloat("--merger-rate", 0.0);
			var mergerK = argInt("--merger-k", 4);
			var mergerInject = argInt("--merger-inject", 4);
			var mergerRng = new musescript.evo.Rand(seed + 7777);
			if (mergerRate > 0) Sys.println('MERGER event: on -- ${Std.int(mergerRate * 100)}% chance/gen, top $mergerK archive genomes, best-of-pairwise hybrid x $mergerInject clones injected');
			// `--sequential-tape` (see the plan's Part D): instead of `--compete` rebuilding (and
			// discarding) a fresh `MurmurationSim` every generation, keep ONE persistent sim per
			// market running across the WHOLE run, with a resident "veteran pool" of past
			// generations' winning genomes still trading in the background -- new generations
			// inject fresh capital ("new money") alongside them, rather than every generation
			// getting an isolated i.i.d. market. Partial turnover, gradually weeded (per the
			// user's explicit answer: relaxed limits, not full replace-every-gen, not unbounded
			// growth) -- see `competeSequentialTapeFitness`'s own doc comment. Off by default;
			// only meaningful alongside `--compete`.
			var sequentialTapeOn = argFlag("--sequential-tape");
			var sequentialTapeVeterans = argInt("--sequential-tape-veterans", pop);
			// A persistent market accumulates tens of thousands of ticks across a long run --
			// observed live (a real 100-generation run) to compound the fundamental's
			// unconstrained random walk into an unbounded trend on one market and a crash toward
			// the tick-size floor on another. See `MurmurationConfig.fundamentalMeanReversion`'s
			// doc comment -- a small per-tick pull back toward `startPrice`, applied ONLY to
			// sequential-tape markets (0.0 -- today's exact existing behavior -- everywhere else).
			var sequentialTapeMeanReversion = argFloat("--sequential-tape-mean-reversion", 0.0005);
			if (sequentialTapeOn) Sys.println('SEQUENTIAL-TAPE: on -- persistent market per compete symbol, veteran cap $sequentialTapeVeterans/market (gradual weeding, partial turnover), fundamental mean-reversion $sequentialTapeMeanReversion');
			// Periodic real-world reality check (`--distill-every`): every N generations,
			// re-score the MAP-Elites archive's top genomes against the REAL `isBasket` data
			// (not whatever synthetic/compete score got them archived) and inject the top
			// real-world performers back into the population -- runs regardless of which mode
			// (real/compete/sequential-tape) is currently active. See `distillReinject`'s doc
			// comment. Off by default (0 = never fires).
			var distillEvery = argInt("--distill-every", 0);
			var distillK = argInt("--distill-k", 8);
			var distillRng = new musescript.evo.Rand(seed + 9999);
			if (distillEvery > 0) Sys.println('DISTILL: on -- every $distillEvery gen(s), re-score top $distillK archive genomes against real data and inject the best performers');
			// Background distillation thread (`--distill-thread`): a continuously-running search
			// on its OWN thread, synthesizing brand-new candidate genomes against the same real
			// `isBasket` data, feeding a queue this loop drains from every generation -- appended
			// directly to `popG` (not slot-replaced), so the population briefly grows for exactly
			// one generation's evaluation before `engine.step` naturally culls it back to `--pop`
			// (the same way gen 0's oversized seed population always has). See the thread-spawn
			// block below (right after `engine`'s own construction) and its own doc comment.
			var distillThreadOn = argFlag("--distill-thread");
			if (distillThreadOn) Sys.println('DISTILL-THREAD: on -- background search continuously synthesizing new genomes against real data');
		// See PLAN_EVO_SPEED.md P1: the attribution oracle (evalFn) is real per-call overhead
		// even with Fitness's compile-cache -- gating how often crossover pays for a full
		// attribution pass (vs cheap blind subtreeCrossover) trades some of that for extra
		// exploration pressure. TESTED via a same-seed 2-seed A/B (0.5/4 vs 1.0/6): seed 123 was
		// a wash (arguably slightly better), but seed 7 was a REAL regression -- IS fitness down
		// (0.74 vs 0.82), OOS hold collapsed to 0/10 (was 7/10), AND it ran SLOWER (752s vs
		// 420s: fewer attribution-guided crossovers means more raw novelty per generation, which
		// means more new WASM compiles/fitness evals elsewhere -- a real, counterintuitive cost
		// that ate the savings). Per the plan's own rule ("do not ship a default that trades
		// measurable OOS quality for speed"), defaults are back to EvolutionEngine.step's own
		// conservative 1.0/6 (unchanged behavior) -- the flags stay available for experimentation,
		// just not silently defaulted on.
		var attrCrossProb = argFloat("--attr-cross-prob", 1.0);
		var donorCap = argInt("--donor-cap", 6);
		// See PLAN_EVO_SPEED.md P2: the attribution oracle needs a RANKING signal ("which node/
		// donor is better"), not full-precision Sharpe -- so by default it reuses the SAME short
		// prefix triage already computes (a real fidelity tradeoff, unlike P0/P1.2/P1.3, so it's
		// the one A/B-gated behind an explicit off switch). `--attr-bars 0` restores the exact
		// old full-tape-oracle behavior.
		var attrBars = argInt("--attr-bars", -1);
		// Live Swing dashboard (see EvoDashboardWindow.hx): off by default, zero impact on every
		// existing headless run. A real native window the JVM's own GUI thread repaints once per
		// generation -- no artifact-polling/republish workaround needed.
		// Human-in-the-loop control surface (see HumanLoopWindow.hx): needs the dashboard's Pause
		// button to ever become visible, so it silently implies --gui rather than requiring both
		// flags to be remembered together.
		var humanLoopOn = argFlag("--human-in-loop");
		var guiOn = argFlag("--gui") || humanLoopOn;
		var dashboard = guiOn ? new EvoDashboardWindow("MuseGene Evolution -- " + (simTapeOn ? "sim-tape (MurmurationSim)" : (tapePath != null ? tapePath : "default tape"))) : null;
		// How often the GUI's performance-vs-benchmark panel re-samples OOS for the WHOLE
		// population -- every generation would double fitness-eval cost (fighting the whole
		// point of PLAN_EVO_SPEED.md) and isn't needed for a live diagnostic view. IS is free
		// (already computed every generation regardless of --gui).
		var guiOosEvery = argInt("--gui-oos-every", 5);

		Sys.println("=== MuseScript CORPUS-SEEDED evolution on GraalWasm ===");
		Sys.println('jvm:  ${java.lang.System.getProperty("java.vm.name")} ${java.lang.System.getProperty("java.vm.version")}');

		// Walk-forward IS/OOS split, applied PER SYMBOL (each keeps its own IS/OOS boundary --
		// symbols may have different lengths/date ranges, so one global bar-index cutoff wouldn't
		// make sense across a basket): evolution only ever sees the IS segment -- fitness,
		// selection, and every generation's ranking are computed exclusively on it. The OOS segment
		// (the last `oosFrac` of each tape, with an `embargo`-bar gap dropped so no indicator's
		// warmup window on the OOS side can reach back across the split) is held out completely
		// until the very end, where it's used ONLY to re-score the final population -- same
		// discipline as the project's own walk-forward validation elsewhere (README/aril page):
		// past and future kept strictly apart, re-scored honestly, not re-tuned to pass.
		var isBasket:Array<Array<Bar>> = [];
		var oosBasket:Array<Array<Bar>> = [];
		if (simTapeOn) {
			#if kestrel
			var simCfg = MurmurationConfigs.withOverrides(
				simConfigPath != null ? haxe.Json.parse(sys.io.File.getContent(simConfigPath)) : null);
			if (simConfigPath == null) simCfg.seed = simSeed; // --sim-seed still applies to the synthetic default
			var sim = new MurmurationSim(simCfg);
			var allBars = MurmurationTape.toBars(sim.run(simSteps));
			var oosLen = Std.int(allBars.length * oosFrac);
			var isLen = allBars.length - oosLen - embargo;
			if (isLen < 200) throw 'sim-tape too short for a ${oosFrac}-fraction OOS split with ${embargo}-bar embargo (${allBars.length} bars total -- raise --sim-steps)';
			isBasket.push(allBars.slice(0, isLen));
			oosBasket.push(allBars.slice(isLen + embargo, allBars.length));
			Sys.println('sim-tape: MurmurationSim seed=$simSeed steps=$simSteps -> ${allBars.length} bars -> IS ${isLen} / embargo $embargo / OOS ${oosBasket[0].length}'
				+ ' (endogenous price, PRICE-TAKING -- see the MurmurationSim x corpus-evo plan\'s Phase 1/2 distinction)');
			#else
			throw "--sim-tape requires a kestrel build (musescript.murmuration is gated behind -D kestrel) -- see build-scratch-simtape.hxml";
			#end
		} else {
			var tapePaths = tapesArg != null ? tapesArg.split(",") : [tapePath];
			for (path in tapePaths) {
				var allBars = loadBars(path);
				var oosLen = Std.int(allBars.length * oosFrac);
				var isLen = allBars.length - oosLen - embargo;
				if (isLen < 200) throw 'tape too short for a ${oosFrac}-fraction OOS split with ${embargo}-bar embargo (${allBars.length} bars total, $path)';
				isBasket.push(allBars.slice(0, isLen));
				oosBasket.push(allBars.slice(isLen + embargo, allBars.length));
				Sys.println('tape: $path -> ${allBars.length} bars total -> IS ${isLen} / embargo $embargo / OOS ${oosBasket[oosBasket.length - 1].length}');
			}
		}
		if (competeRequested) {
			#if !kestrel
			throw "--compete/--schedule (a compete segment) requires a kestrel build (musescript.murmuration is gated behind -D kestrel) -- see build-scratch-simtape.hxml";
			#end
		}
		if (isBasket.length > 1) Sys.println('multi-symbol basket: ${isBasket.length} symbols, fitness aggregated via BasketFitness.aggregateBasket (mean sharpe, summed trades/equity)');
		// `bars`/`oosBars` stay bound to basket[0] -- every existing single-tape code path below
		// (triage, the attribution oracle, the GUI's periodic OOS re-sample) is DELIBERATELY kept
		// scoped to just this one representative symbol for speed, the same "trade fidelity for
		// speed" reasoning the triage prefix itself already uses (see below) extended one level
		// further. Only the full per-generation population eval (the WASM/fallback worker pools)
		// and the final top-10 OOS re-score actually run the WHOLE basket.
		var bars = isBasket[0];
		var oosBars = oosBasket[0];
		if (!sys.FileSystem.exists(watDir)) sys.FileSystem.createDirectory(watDir);

		// Buy-and-hold benchmark for the GUI's performance panel: "mean performance of the
		// symbol(s) being evaluated" -- a plain always-long genome run through the SAME
		// Fitness.evaluate/OrderSim/cost-model path as every other genome (real entry slippage
		// included, not a theoretical zero-cost number), so it's directly comparable to genome
		// Sharpes on the same axis. Computed ONCE, not per generation -- it's a fixed property
		// of the tape(s) + cost, not of the population. Basket mode: mean across ALL symbols (not
		// just basket[0]) -- unlike triage/the attribution oracle, this is a one-time, cheap
		// computation (one eval per symbol), so there's no reason to shortcut it to one symbol.
		var isBenchmark = 0.0, oosBenchmark = 0.0;
		if (guiOn) {
			var buyHold:StrategyGenome = {
				entryLong: BCmp(">", KConst(1.0), KConst(0.0)), // always true
				entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
				exitLong: BCmp(">", KConst(0.0), KConst(1.0)), // never exits
				exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
				size: KConst(1.0), params: [], name: "buy_and_hold", lineage: [], seedOrigin: null
			};
			var isSum = 0.0, oosSum = 0.0;
			for (i in 0...isBasket.length) {
				var isBH = Fitness.evaluate(buyHold, isBasket[i], "js", false, costBps);
				var oosBH = Fitness.evaluate(buyHold, oosBasket[i], "js", false, costBps);
				isSum += isBH.ok ? isBH.sharpe : 0.0;
				oosSum += oosBH.ok ? oosBH.sharpe : 0.0;
			}
			isBenchmark = isSum / isBasket.length;
			oosBenchmark = oosSum / isBasket.length;
			Sys.println('buy-and-hold benchmark: IS sharpe=${fmt(isBenchmark, 4)}  OOS sharpe=${fmt(oosBenchmark, 4)}' + (isBasket.length > 1 ? ' (mean across ${isBasket.length} symbols)' : ''));
		}

		var cacheDir = "build/graal/evo-cache";
		if (!noCache && !sys.FileSystem.exists(cacheDir)) sys.FileSystem.createDirectory(cacheDir);
		// Cache filename includes costBps -- a fitness memo keyed on tape content ALONE would
		// silently reuse stale zero-cost (or different-cost) fitness numbers the moment `--cost-bps`
		// changes between runs on the SAME tape, which is exactly the kind of silent staleness this
		// whole cache existed to avoid causing (see EvoCache.hx's doc comment). `costBps` is now
		// part of what "the same evaluation" means, same as the bars themselves.
		// `bankruptSuffix`: the on-disk fitness memo is keyed by (structural key, tape signature)
		// alone, with no room for "was this evaluated under a capital constraint" -- reusing a
		// plain cache's entries under `--equity-floor` would silently readmit genomes that were
		// never actually solvency-tested. Namespacing the cache filename by capital/floor keeps a
		// bankruptcy-crank run's memo fully separate; `--equity-floor 0` (the default) hashes to
		// the exact same filename as before this flag existed.
		var bankruptSuffix = equityFloor > 0 ? '_cap${Std.int(startCapital)}_floor${Std.int(equityFloor)}' : '';
		// `difficultyScheduleOn` forces a null (in-memory-only) cache path -- a per-generation
		// capital/floor ramp has no single (capital, floor) pair to namespace a disk file by, and
		// `cache.clear()` (see the generation loop) already wipes it in-memory every time the ramp
		// actually changes either value, so persisting to disk would just be writing entries that
		// are about to be discarded.
		// `fitnessWindows > 1` also skips disk persistence, same reasoning as
		// `difficultyScheduleOn` right above it: a cached `sharpe` now means "robustness-adjusted
		// across N windows," not the plain whole-tape number an older on-disk file would hold --
		// silently warm-starting from that would score SOME genomes (cache hits) on the old
		// yardstick and others (fresh evals) on the new one within the SAME run. Simplest correct
		// fix is the one this codebase already uses for an analogous "the memo's meaning changed"
		// case: no disk file at all, in-memory-only for the run's own duration.
		var cachePath = (noCache || difficultyScheduleOn || fitnessWindows > 1) ? null : '$cacheDir/${EvoCache.basketSignature(isBasket)}_cost${Std.int(costBps * 10)}$bankruptSuffix.tsv';
		var cache = new EvoCache(cachePath);
		if (cachePath != null) Sys.println('fitness cache: $cachePath (warm-started ${cache.size()} entries)');

		// Auto-size the triage prefix to a fifth of the IS tape; keep it long enough for the
		// slower indicators to warm up (a too-short prefix would score every genome as a
		// no-warmup no-op and triage on noise), and never triage if the prefix would be the whole
		// tape anyway (short tapes -- then full eval IS the prefix eval, no point paying twice).
		if (triageBars < 0) triageBars = Std.int(bars.length / 5);
		if (triageBars > bars.length) triageBars = bars.length;
		var triageOn = triageBars >= 60 && triageBars < bars.length && triageKeep < 0.999;
		var prefixBars = triageOn ? bars.slice(0, triageBars) : null;
		var triageCache = (triageOn && !noCache && !difficultyScheduleOn) ? new EvoCache('$cacheDir/${EvoCache.tapeSignature(prefixBars)}_cost${Std.int(costBps * 10)}.tsv') : new EvoCache(null);
		if (triageOn)
			Sys.println('fallback triage: prefix ${triageBars} bars, keep top ${Std.int(triageKeep * 100)}% (warm-started ${triageCache.size()} prefix evals)');
		if (equityFloor > 0 && !difficultyScheduleOn)
			Sys.println('bankruptcy crank: on (start capital ${startCapital}, equity floor ${equityFloor} -- ALL genomes forced to the JS-fallback backend to honor it, WASM path skipped entirely)');
		if (difficultyScheduleOn)
			Sys.println('bankruptcy DIFFICULTY SCHEDULE: on -- capital ramps ${startCapital} -> ${difficultyEndCapital}, equity floor ramps ${equityFloor} -> ${difficultyEndFloor} over $gens generations'
				+ ' (ALL genomes forced to JS-fallback; fitness cache in-memory-only, wiped whenever the ramp changes capital/floor)');

		// Per-mode archives (see `--schedule`'s doc comment): a shared archive would let an
		// inflated compete z-score permanently squat a behavioral cell over a genuinely-better
		// real-tape sharpe (or vice versa) purely from scale, not real merit -- the two fitness
		// scales aren't comparable, so "does this beat the cell's current occupant" needs to stay
		// scoped to genomes scored the SAME way. `archive` itself is a plain mutable ALIAS,
		// reassigned to whichever mode is active every generation (see the `--schedule` block at
		// the top of the loop) -- every existing `archive.offer`/`.summary()`/etc. call site below
		// needs zero changes, they just operate on whichever underlying archive is current.
		var archiveReal = new EliteArchive();
		var archiveCompete = new EliteArchive();
		var archive = competeOn ? archiveCompete : archiveReal;
		var immigrantRng = new musescript.evo.Rand(seed + 991);
		if (mapElitesOn) Sys.println('MAP-Elites: on (immigrant rate ${Std.int(immigrantRate * 100)}% of non-elite slots/gen)');

		var tuner = new musescript.evo.GrowthWeights();
		tuner.enabled = tunerOn;
		if (tunerOn && tunerPath != null) { tuner.load(tunerPath); Sys.println('growth tuner: warm-started from $tunerPath'); }
		Sys.println(tunerOn ? 'growth tuner: on (reward loop closed via attributedPointMutate)' : 'growth tuner: off (--no-tuner, using literal defaults)');

		var surrogate = new SurrogateModel();
		if (surrogateOn && surrogatePath != null) { surrogate.load(surrogatePath); Sys.println('surrogate model: warm-started from $surrogatePath (${surrogate.samplesSeen} samples seen previously)'); }
		if (surrogateOn) Sys.println('surrogate pre-filter: on (keep top ${Std.int(surrogateKeep * 100)}% by predicted fitness before triage)');

		// --- build the seed population --------------------------------------------------
		var allowed = new Map<String, Bool>();
		for (n in RegistryPalette.compatibleNames()) allowed.set(n, true);

		var tournament = CorpusSeed.seedFromDirectory(corpusDir, allowed);
		Sys.println('tournament corpus: ${tournament.total} files, ${tournament.genomes.length} translated to genomes, ${tournament.skipped.length} skipped (outside the closed GP grammar -- onPosition exits, multi-output field access, etc.)');

		// fourier_projection is excluded from the generic indicator list here -- seedFromIndicators'
		// 2-arg SInd-based crossover leaves k/horizon at spec defaults (horizon=1), which was
		// confirmed catastrophic (thousands of trades, sharpe -3 to -5). seedFromFourierProjection
		// below gives it a proper custom-parameterized, edge-triggered seed instead.
		var indicatorNames = [for (n in allowed.keys()) if (n != "fourier_projection") n];
		var indicatorSeeds = CorpusSeed.seedFromIndicators(indicatorNames);
		Sys.println('indicator seeds: ${indicatorNames.length} compatible indicators x 3 windows = ${indicatorSeeds.length} genomes');

		// fib_retracement/fourier_projection don't fit the generic seedFromIndicators path at all
		// (see seedFromFibRetracement's/seedFromFourierProjection's own doc comments) -- both use
		// edge-triggered crossings against a KFeature bare-expression leaf instead of a bare level
		// condition, after the first (level-condition) attempt at these seeds proved catastrophic
		// on a real tape (IS sharpe -2.3 to -4.8, hundreds to thousands of trades).
		var fibSeeds = CorpusSeed.seedFromFibRetracement();
		var fourierSeeds = CorpusSeed.seedFromFourierProjection();
		Sys.println('fib_retracement seeds: ${fibSeeds.length} genomes (3 windows x breakout/reclaim)');
		Sys.println('fourier_projection seeds: ${fourierSeeds.length} genomes (2 custom smoothed configs)');

		var seedPop = tournament.genomes.concat(indicatorSeeds).concat(fibSeeds).concat(fourierSeeds);
		Sys.println('seeded generation 0: ${seedPop.length} real genomes (${tournament.genomes.length} corpus-derived + ${indicatorSeeds.length} indicator-derived + ${fibSeeds.length} fib-retracement + ${fourierSeeds.length} fourier-projection)');

		// Own Variation instance, deliberately independent of `engine`'s internal one -- candidate
		// generation for a human browsing the population has no business perturbing the main run's
		// RNG stream/reproducibility. `seed + 5000` just needs to not collide with any other seed
		// offset already in use (immigrantRng uses `seed + 991`).
		var humanLoop = humanLoopOn
			? new HumanLoopWindow("MuseGene Human-in-the-Loop", new Variation(seed + 5000, indicatorNames, tuner), bars, costBps, allowed)
			: null;
		if (humanLoopOn) Sys.println("human-in-the-loop: on -- browse/edit/inject via the editor window");

		// Own Variation instance for the merger event's crossover/mutate ops, deliberately
		// independent of `engine`'s internal one for the same reason `humanLoop`'s is -- a rare,
		// out-of-band event has no business perturbing the main run's RNG stream. `seed + 8888`
		// avoids the offsets already in use (`immigrantRng` +991, `humanLoop`'s Variation +5000,
		// `mergerRng` +7777).
		var mergerVariation = new Variation(seed + 8888, indicatorNames, tuner);

		var engineOpts = ["engine.LastTierCompilationThreshold" => "2000000000"];
		var host = new GraalWasmHost(null, engineOpts);
		host.costBps = costBps;
		Sys.println('transaction cost: ${costBps}bps slippage on every entry+exit (--cost-bps 0 to disable)');

		var engine = new EvolutionEngine(seed, pop, Std.int(Math.max(2, pop / 16)), 3, null, tuner);
		var popG = seedPop;

		// Background distillation thread (`--distill-thread`): a continuously-running search on
		// its OWN thread, synthesizing brand-new candidate genomes against the real `isBasket`
		// data and feeding a queue the main loop drains from every generation. Fully independent
		// of the main run's population/engine/RNG -- its own `EvolutionEngine`+`Variation` pair
		// (own seed offset, own tiny local population, `tuner: null` so it never touches the main
		// run's shared growth-tuner state), reads `isBasket`/`costBps`/`startCapital`/
		// `equityFloor`/`indicatorNames` READ-ONLY (never mutated by anything but the difficulty
		// ramp reassigning `startCapital`/`equityFloor` wholesale, which this thread just picks up
		// the latest value of on its next read -- consistent with the main run's own ramp, not a
		// race), and communicates ONLY via its own output `Deque` -- exactly the same "never touch
		// `popG`/`keyToIdx`/`archive` directly" discipline the existing WASM/fallback pools rely
		// on. Uses only the "js" interpreter backend (no shared GraalWasmHost/native engine state
		// to worry about across threads), same as the existing fallback pool.
		var distillOutQueue = new Deque<Array<StrategyGenome>>();
		var distillStopQueue = new Deque<{stop:Bool}>();
		if (distillThreadOn) {
			Thread.create(function() {
				var distillVariation = new Variation(seed + 13000, indicatorNames, null);
				var distillEngine = new EvolutionEngine(seed + 13000, 24, 3, 3, indicatorNames, null);
				var distillPickRng = new musescript.evo.Rand(seed + 13001);
				function evalOne(g:StrategyGenome):Float {
					var anyErr = false;
					var perSymbol:Array<{trades:Int, sharpe:Float, finalEquity:Float}> = [];
					for (sym in isBasket) {
						var fr = Fitness.evaluate(g, sym, "js", false, costBps, startCapital, equityFloor);
						if (!fr.ok || fr.bankrupt) { anyErr = true; break; }
						perSymbol.push({trades: fr.trades, sharpe: fr.sharpe, finalEquity: fr.finalEquity});
					}
					if (anyErr) return Fitness.NEG_INF;
					var agg = BasketFitness.aggregateBasket(perSymbol);
					return (agg.trades >= 1 && !Math.isNaN(agg.sharpe)) ? agg.sharpe : Fitness.NEG_INF;
				}
				while (distillStopQueue.pop(false) == null) {
					// Fresh reseed each cycle (variety across cycles, cheap to build) -- a random
					// subset of indicator names, not the full corpus, keeping this micro-search cheap.
					var pool = indicatorNames.copy();
					for (i in 0...pool.length - 1) {
						var j = i + distillPickRng.int(pool.length - i);
						var t = pool[i]; pool[i] = pool[j]; pool[j] = t;
					}
					var miniPop = CorpusSeed.seedFromIndicators(pool.slice(0, Std.int(Math.min(pool.length, 24))));
					if (miniPop.length == 0) continue;
					var fitness = [for (g in miniPop) evalOne(g)];
					for (_ in 0...5) {
						miniPop = distillEngine.step(miniPop, fitness, evalOne, 0.0, 6, 0.0);
						fitness = [for (g in miniPop) evalOne(g)];
					}
					var ranked = [for (i in 0...miniPop.length) {g: miniPop[i], f: fitness[i]}];
					ranked.sort((a, b) -> a.f < b.f ? 1 : (a.f > b.f ? -1 : 0));
					var winners = [for (r in ranked) if (r.f != Fitness.NEG_INF) r.g];
					if (winners.length > 3) winners = winners.slice(0, 3);
					if (winners.length > 0) distillOutQueue.add(winners);
				}
			});
		}
		// `--compete-symbols > 1`: each individual's co-evolved market-selection preference (see
		// SymbolSelector.hx), parallel to `popG` -- index i's selector pairs with popG[i]. Market
		// configs/features are built ONCE here (fixed "symbol identities" the whole run competes
		// over); only each market's underlying price REALIZATION is regenerated every generation
		// (see `competeMultiMarketFitness`'s per-market seed).
		#if kestrel
		var marketConfigs:Array<MurmurationConfig> = [];
		var marketFeatures:Array<Array<Float>> = [];
		var selectorRng = new musescript.evo.Rand(seed + 6001);
		var selectors:Array<SymbolSelector> = competeSymbols > 1 ? [for (_ in 0...popG.length) new SymbolSelector(4, selectorRng)] : null;
		// `--sequential-tape` needs `marketConfigs`/`marketFeatures` built even when
		// `competeSymbols == 1` (a single-market persistent sim is still "one market" to the
		// sequential-tape machinery below) -- only the SELECTOR population above stays gated to
		// `competeSymbols > 1` (a lone market needs no market-choice at all).
		if (competeSymbols > 1 || sequentialTapeOn) {
			var baseCfg = MurmurationConfigs.defaults();
			var rawFeatures:Array<Array<Float>> = [];
			for (m in 0...competeSymbols) {
				var t = competeSymbols > 1 ? m / (competeSymbols - 1) : 0.0; // 0=calm/deep-liquidity .. 1=volatile/thin
				var cfg = MurmurationConfigs.defaults();
				cfg.fundamentalVol = baseCfg.fundamentalVol * (0.3 + t * 2.0);
				cfg.marketFactorVol = baseCfg.marketFactorVol * (0.3 + t * 2.0);
				cfg.impact = baseCfg.impact * (0.5 + t * 1.5);
				cfg.mixMarketMaker = Math.max(0.02, baseCfg.mixMarketMaker * (1.0 - t * 0.7));
				// Scale the reversion pull by this market's OWN place on the calm<->volatile axis
				// (the same `t` used to build its impact/liquidity above) -- a flat coefficient
				// tamed the calm market but was observed live to be far too weak against the
				// volatile market's much higher impact + thinner liquidity (it kept climbing
				// steadily regardless). The volatile end needs a proportionally stronger pull
				// simply because it's built to move more per unit of trading pressure.
				if (sequentialTapeOn) cfg.fundamentalMeanReversion = sequentialTapeMeanReversion * (1.0 + t * 4.0);
				marketConfigs.push(cfg);
				rawFeatures.push([cfg.fundamentalVol, cfg.marketFactorVol, cfg.impact, cfg.mixMarketMaker]);
			}
			// Min-max normalize each feature COLUMN across the market set to [0,1] before handing
			// it to `SymbolSelector.score` -- the 4 raw config knobs span wildly different units/
			// magnitudes (vol ~1e-3, impact ~1e-1), so a freshly-initialized selector's random
			// Gaussian weights would otherwise be dominated by whichever feature happens to have
			// the largest raw magnitude, regardless of its actual weight -- not a real preference,
			// just a unit-scale artifact. Normalizing puts every feature on equal footing so the
			// CO-EVOLVED weights (not raw units) are what actually drives which markets look
			// attractive.
			marketFeatures = [for (_ in 0...competeSymbols) [for (_ in 0...4) 0.0]];
			for (f in 0...4) {
				var lo = rawFeatures[0][f], hi = rawFeatures[0][f];
				for (m in 0...competeSymbols) { if (rawFeatures[m][f] < lo) lo = rawFeatures[m][f]; if (rawFeatures[m][f] > hi) hi = rawFeatures[m][f]; }
				var span = hi - lo;
				for (m in 0...competeSymbols) marketFeatures[m][f] = span > 1e-12 ? (rawFeatures[m][f] - lo) / span : 0.5;
			}
			Sys.println('  markets: ' + [for (i in 0...competeSymbols) '#$i(vol=${fmt(marketConfigs[i].fundamentalVol, 4)} impact=${fmt(marketConfigs[i].impact, 2)} mm=${fmt(marketConfigs[i].mixMarketMaker, 2)} normFeatures=${marketFeatures[i]})'].join(" "));
		}
		// Sequential-tape persistent state (see `competeSequentialTapeFitness`'s doc comment):
		// one `MurmurationSim` + one resident "veteran pool" per market, built lazily on first
		// use (gen 0) rather than here, so the sim's ONE-TIME construction seed can still be
		// derived the same way every other compete path derives its per-generation seed. The
		// evolved-slot pool per market is bounded by `--compete-agents` itself (gen 0 alone can
		// carry the whole seeded corpus as newcomers) -- `--compete-agents` must be raised if
		// this bound doesn't fit (checked at first use, same "clear error, not silent
		// misbehavior" discipline as `competeGenerationFitness`'s own `--compete-agents` check).
		var persistentSims:Array<MurmurationSim> = sequentialTapeOn ? [for (_ in 0...marketConfigs.length) null] : null;
		// `lastWealth` -- the veteran's mark-to-market wealth as of the last time IT was
		// evaluated (set at graduation, then re-baselined every generation it survives eviction)
		// -- see `competeSequentialTapeFitness`'s eviction step for why this matters: ranking
		// eviction by LIFETIME wealth let a veteran who caught one huge early move sit at the top
		// forever regardless of how stale or how large its position had since grown, which is
		// exactly what let individual agents accumulate unboundedly large one-directional
		// inventory (confirmed live via a net-inventory diagnostic) instead of being cycled out
		// once their edge stopped paying off.
		var veteranPools:Array<Array<{agentId:Int, genome:StrategyGenome, key:String, lastWealth:Float}>> =
			sequentialTapeOn ? [for (_ in 0...marketConfigs.length) []] : null;
		var noOpDecide = function(_:Bar):{side:Int, qty:Float} return {side: 0, qty: 0.0};
		#end
		// Per-MODE snapshots (see `--schedule`'s doc comment) -- a real-tape sharpe and a compete
		// z-score aren't comparable, so "final generation's IS fitness for the holdout re-score"
		// needs to be tracked separately per mode: whichever mode last ran gets its own snapshot,
		// used later by ITS OWN holdout-check block, not a single shared array that the other
		// mode's numbers would silently overwrite.
		var lastFitnessReal:Array<Float> = null;
		var lastFitnessCompete:Array<Float> = null;
		// Hoisted OUT of the per-generation loop (reassigned there, not re-`var`-declared) so the
		// PERSISTENT fallback worker pool below -- created once, before the loop -- can close over
		// this slot at all; a `var` declared fresh inside the loop wouldn't exist yet at the point
		// the pool's lambdas are defined, which is a compile error, not just a staleness risk.
		var keyToIdx:Map<String, Array<Int>> = new Map();

		var moduleCache = new Map<String, ModuleEntry>();
		var unsupportedKeys = new Map<String, Bool>();
		// Per-mode all-time champions -- see `--schedule`'s doc comment for why a single `best`
		// comparing across a real-tape sharpe and a compete z-score would be meaningless.
		var bestReal = Fitness.NEG_INF;
		var bestGenomeReal:StrategyGenome = null;
		var bestCompete = Fitness.NEG_INF;
		var bestGenomeCompete:StrategyGenome = null;
		var totalT0 = haxe.Timer.stamp();

		// Adversarial curriculum weighting (`--curriculum`, see BasketFitness.aggregateBasket's
		// `weights` param): starts uniform (mathematically identical to the plain mean
		// `aggregateBasket` uses when `weights == null`), MUTATED IN PLACE (element-by-element,
		// never reassigned wholesale) at the end of each generation below, to bias future
		// generations' basket-mean toward whichever symbols the population is currently worst at.
		// This same array OBJECT gets handed to `evalWorker` as an ordinary function parameter
		// (not a closure capture) -- in-place mutation is what makes later updates visible through
		// that parameter reference; a wholesale reassignment (`curriculumWeights = [...]`) would
		// NOT be, since the worker's own parameter binding was fixed at Thread.create time.
		var curriculumWeights:Array<Float> = [for (_ in isBasket) 1.0];

		var jobQueue = new Deque<EvalJob>();
		var resultQueue = new Deque<EvalResult>();
		var ackQueue = new Deque<Int>();
		for (_ in 0...threads) {
			var sharedEngine = host.engine;
			Thread.create(function() evalWorker(sharedEngine, isBasket, jobQueue, resultQueue, ackQueue, costBps, curriculumOn ? curriculumWeights : null));
		}

		// P3 (see PLAN_EVO_SPEED.md): the JS/interp fallback loop (genomes StrategyWasmEmitter
		// can't natively lower) was the last serial-on-the-main-thread hot path -- worker-pooled
		// the SAME way the WASM path already is, gated on a real concurrency probe (see the plan)
		// confirming Fitness.evaluate produces byte-identical results under concurrent access
		// (genome-expanded source routes stateful builtins through CallsiteIds' per-callsite-id,
		// harness-local state, never the legacy JVM-wide static slots). Persistent pool, same
		// dispatch-N/collect-N discipline as the WASM pool -- the main thread always blocks until
		// every dispatched job's result is collected before `popG`/`keyToIdx` get reassigned for
		// the next generation, so a worker reading those captured (not copied) variables always
		// sees the CURRENT generation's data, never a stale or future one.
		var fbJobQueue = new Deque<FallbackJob>();
		var fbResultQueue = new Deque<FallbackResult>();
		for (_ in 0...Std.int(Math.max(1, threads))) {
			Thread.create(function() {
				while (true) {
					var job = fbJobQueue.pop(true);
					if (job.stop) return;
					var g = popG[keyToIdx.get(job.key)[0]];
					if (!job.useFullTape) {
						// Triage prefix eval: stays scoped to basket[0]'s prefix, same as before --
						// see CorpusEvoRun's `isBasket` doc comment.
						var fr = Fitness.evaluate(g, prefixBars, "js", false, costBps, startCapital, equityFloor);
						// `perSymbolSharpe: []` -- this is a triage-prefix eval, not a full basket
						// pass, so there's no real per-symbol breakdown to hand back (curriculum
						// weighting only ever reads this field from the PROMOTED/full-basket branch
						// below).
						fbResultQueue.add(fr.ok
							? { key: job.key, ok: true, trades: fr.trades, sharpe: fr.sharpe, equity: fr.finalEquity, fills: fr.fills, perSymbolSharpe: [], bankrupt: fr.bankrupt }
							: { key: job.key, ok: false, trades: 0, sharpe: Math.NaN, equity: 0, fills: null, perSymbolSharpe: [], bankrupt: false });
					} else {
						// Promoted (survived triage): the FULL basket, aggregated -- see
						// BasketFitness.aggregateBasket. A single-symbol run's `isBasket` is a
						// one-element array, so this loop runs once and degenerates to exactly the
						// old single-tape behavior for any valid result.
						var perSymbol:Array<{trades:Int, sharpe:Float, finalEquity:Float}> = [];
						var firstFills = null;
						var anyErr = false;
						var anyBankrupt = false;
						for (i in 0...isBasket.length) {
							var fr = Fitness.evaluate(g, isBasket[i], "js", false, costBps, startCapital, equityFloor);
							if (!fr.ok) { anyErr = true; break; }
							if (i == 0) firstFills = fr.fills;
							if (fr.bankrupt) anyBankrupt = true;
							// This IS the main per-generation selection signal (feeds `CachedEval.
							// sharpe`, which `scoreOf` applies parsimony on top of) -- the robustness
							// window applies HERE, per-symbol, before `BasketFitness.aggregateBasket`
							// combines symbols (aggregation is just a mean/sum regardless of what each
							// symbol's own "sharpe" represents, so this composes correctly).
							var symSharpe = fitnessWindows > 1 ? Fitness.robustScore(fr, fitnessWindows, fitnessWindowLambda) : fr.sharpe;
							perSymbol.push({trades: fr.trades, sharpe: symSharpe, finalEquity: fr.finalEquity});
						}
						if (anyErr) {
							fbResultQueue.add({key: job.key, ok: false, trades: 0, sharpe: Math.NaN, equity: 0, fills: null, perSymbolSharpe: [], bankrupt: false});
						} else {
							var agg = BasketFitness.aggregateBasket(perSymbol, curriculumOn ? curriculumWeights : null);
							fbResultQueue.add({key: job.key, ok: true, trades: agg.trades, sharpe: agg.sharpe, equity: agg.finalEquity, fills: firstFills,
								perSymbolSharpe: [for (p in perSymbol) p.sharpe], bankrupt: anyBankrupt});
						}
					}
				}
			});
		}

		// Soft-cap parsimony scoring from a raw eval (see Fitness.score's doc comment for the
		// threshold/lambda semantics) -- one definition used everywhere a CachedEval becomes a
		// selectable fitness, so the WASM path and the JS-fallback path can never drift apart the
		// way they did before this was a shared function.
		var scoreOf = function(e:CachedEval, nodes:Int):Float {
			if (e == null || e.trades < 1 || Math.isNaN(e.sharpe)) return Fitness.NEG_INF;
			if (e.bankrupt == true) return Fitness.NEG_INF; // bankruptcy crank: no sharpe survives going bust
			var s = e.sharpe;
			if (nodes > parsimonyThreshold) s -= parsimonyLambda * (nodes - parsimonyThreshold);
			return s;
		};

		// Training target for SurrogateModel.update: an invalid eval (no trades / NaN sharpe, i.e.
		// what scoreOf would call Fitness.NEG_INF) is clamped to a bounded "very bad" sentinel
		// instead of feeding a literal -Infinity into the LMS update, which would blow the weights
		// up instantly. The model only needs to learn "genomes shaped like this tend to be bad," not
		// the exact magnitude of NEG_INF.
		var SURROGATE_INVALID_SENTINEL = -3.0;
		var surrogateTarget = function(e:CachedEval):Float {
			if (e == null || e.trades < 1 || Math.isNaN(e.sharpe)) return SURROGATE_INVALID_SENTINEL;
			return e.sharpe;
		};

		// `--compete`'s fitness path: run every unique genome as an `Evolved` agent in ONE shared
		// MurmurationSim, then score each by mark-to-market wealth Z-SCORED against the cohort
		// (mean 0, unit std within THIS generation's competitors) -- invariant to a uniform wealth
		// shift across the whole cohort, per the plan's "relative, not absolute" design goal.
		// `#if kestrel`-gated like `--sim-tape`; `--compete` throws a clear error at startup below
		// if used on a non-kestrel build, so this function is simply never called otherwise.
		#if kestrel
		function competeGenerationFitness(genomesByKey:Array<{key:String, g:StrategyGenome}>, agents:Int, steps:Int, competeSeed:Int):Map<String, Float> {
			if (genomesByKey.length > agents)
				throw '--compete-agents ($agents) must exceed this generation\'s unique genome count (${genomesByKey.length}) -- raise --compete-agents';
			var cfg = MurmurationConfigs.defaults();
			cfg.nAgents = agents;
			cfg.seed = competeSeed;
			var sim = new MurmurationSim(cfg);
			var pop = sim.population();
			var steppers = [for (gk in genomesByKey) new GenomeStepper(gk.g)];
			for (i in 0...genomesByKey.length) pop.setEvolvedAgent(i, steppers[i].decide);
			var rows = sim.run(steps);
			var faulted = 0;
			for (s in steppers) if (s.faulted) faulted++;
			if (faulted > 0) {
				Sys.println('  compete: $faulted/${steppers.length} genomes faulted mid-run and stopped trading (see GenomeStepper.decide\'s doc comment)');
				// Surface WHAT actually broke, not just how many -- `faultReason` was tracked but
				// never printed anywhere, so a spike in fault rate (e.g. ALL top performers
				// faulting on a fresh-market re-check) had no way to be diagnosed short of adding
				// this print. Deduplicated: the same root cause typically hits every genome that
				// shares whatever triggered it, so a handful of DISTINCT messages is more useful
				// than one line per genome.
				var seenReasons = new Map<String, Bool>();
				var shown = 0;
				for (s in steppers) {
					if (!s.faulted || s.faultReason == null || seenReasons.exists(s.faultReason)) continue;
					seenReasons.set(s.faultReason, true);
					Sys.println('    fault: ${s.faultReason}');
					shown++;
					if (shown >= 5) break;
				}
			}
			var finalPrice = rows[rows.length - 1].close;
			var wealth = [for (i in 0...genomesByKey.length) pop.markToMarket(i, finalPrice)];
			var mean = 0.0;
			for (w in wealth) mean += w;
			mean /= wealth.length;
			var variance = 0.0;
			for (w in wealth) variance += (w - mean) * (w - mean);
			variance /= wealth.length;
			var std = Math.sqrt(variance);
			var zscores = [for (w in wealth) std > 1e-9 ? (w - mean) / std : 0.0];
			// MAP-Elites archive offering (see the non-compete eval-and-score block's own offer
			// call for the pattern this mirrors) -- was previously skipped entirely in compete
			// mode (no `CachedEval`-shaped `e` naturally exists here), which made `--gui`'s niche
			// panels always read 0/48 regardless of how diverse the cohort actually was. Each
			// genome's OWN private-ledger fills (GenomeStepper.fills, not the real auction
			// settlement) drive the SAME behavioral descriptors a tape-based eval would use --
			// niching is about what the strategy DECIDED to do, same reasoning as the tape path.
			// Z-SCORE (not raw wealth) as the archive's comparison fitness: wealth's absolute scale
			// isn't comparable across generations (a fresh sim/seed every time), but a z-score is
			// always "how many std devs above this generation's own cohort mean" -- stays roughly
			// comparable enough for archive purposes across the whole run.
			if (mapElitesOn) {
				for (i in 0...genomesByKey.length) {
					if (steppers[i].faulted || steppers[i].tradeCount() < 1) continue;
					var desc = MapElites.describeFills(steppers[i].fills(), steps);
					var tradesPerBar = steppers[i].tradeCount() / steps;
					var ck = MapElites.cellKey(tradesPerBar, desc.avgHold, desc.longFrac);
					archive.offer(genomesByKey[i].g, zscores[i], ck, tradesPerBar, desc.avgHold, desc.longFrac);
				}
			}
			var out = new Map<String, Float>();
			for (i in 0...genomesByKey.length) out.set(genomesByKey[i].key, zscores[i]);
			return out;
		}

		/**
		 * `--compete-symbols > 1`: each INDIVIDUAL (population index, NOT deduped by structural
		 * genome key like `competeGenerationFitness` above) picks a market via its own co-evolved
		 * `SymbolSelector`, then trades in a per-market cohort z-scored the SAME way. Deduping by
		 * genome key doesn't apply here -- two individuals can share an IDENTICAL trading genome
		 * but carry DIFFERENT (independently co-evolved) selectors, so the same genome might need
		 * evaluating in two different markets. A real efficiency cost vs the single-market path
		 * (no key-dedup, no cross-generation cache), accepted for v1 -- see the plan's own
		 * "Cost" note.
		 */
		function competeMultiMarketFitness(individuals:Array<StrategyGenome>, selectorsArr:Array<SymbolSelector>,
				marketConfigs:Array<MurmurationConfig>, marketFeatures:Array<Array<Float>>, agentsPerMarket:Int, steps:Int, competeSeed:Int):Array<Float> {
			var n = individuals.length;
			var chosenMarket = [for (i in 0...n) {
				var bestM = 0;
				var bestScore = selectorsArr[i].score(marketFeatures[0]);
				for (m in 1...marketFeatures.length) {
					var s = selectorsArr[i].score(marketFeatures[m]);
					if (s > bestScore) { bestScore = s; bestM = m; }
				}
				bestM;
			}];
			var fitness = [for (_ in 0...n) 0.0];
			var marketCounts = [for (_ in marketConfigs) 0];
			for (m in 0...marketConfigs.length) {
				var groupIdx = [for (i in 0...n) if (chosenMarket[i] == m) i];
				marketCounts[m] = groupIdx.length;
				if (groupIdx.length == 0) continue;
				var cfg = marketConfigs[m];
				cfg.nAgents = Std.int(Math.max(agentsPerMarket, groupIdx.length));
				cfg.seed = competeSeed + m * 100003; // distinct-but-deterministic per market+gen
				var sim = new MurmurationSim(cfg);
				var pop = sim.population();
				var steppers = [for (i in groupIdx) new GenomeStepper(individuals[i])];
				for (k in 0...groupIdx.length) pop.setEvolvedAgent(k, steppers[k].decide);
				var rows = sim.run(steps);
				var faulted = 0;
				for (s in steppers) if (s.faulted) faulted++;
				if (faulted > 0) Sys.println('  compete[market $m]: $faulted/${steppers.length} genomes faulted mid-run and stopped trading');
				var finalPrice = rows[rows.length - 1].close;
				var wealth = [for (k in 0...groupIdx.length) pop.markToMarket(k, finalPrice)];
				var mean = 0.0;
				for (w in wealth) mean += w;
				mean /= wealth.length;
				var variance = 0.0;
				for (w in wealth) variance += (w - mean) * (w - mean);
				variance /= wealth.length;
				var std = Math.sqrt(variance);
				for (k in 0...groupIdx.length) {
					var z = std > 1e-9 ? (wealth[k] - mean) / std : 0.0;
					fitness[groupIdx[k]] = z;
					if (mapElitesOn && !steppers[k].faulted && steppers[k].tradeCount() >= 1) {
						var desc = MapElites.describeFills(steppers[k].fills(), steps);
						var tradesPerBar = steppers[k].tradeCount() / steps;
						var ck = MapElites.cellKey(tradesPerBar, desc.avgHold, desc.longFrac);
						archive.offer(individuals[groupIdx[k]], z, ck, tradesPerBar, desc.avgHold, desc.longFrac);
					}
				}
			}
			Sys.println('  markets chosen: ' + [for (m in 0...marketConfigs.length) '#$m=${marketCounts[m]}'].join(" "));
			return fitness;
		}

		/**
		 * `--sequential-tape`: unlike `competeGenerationFitness`/`competeMultiMarketFitness`
		 * (fresh `MurmurationSim` every call, discarded after), this reuses ONE PERSISTENT sim
		 * per market (`persistentSims[m]`, built once on first use) plus a resident "veteran
		 * pool" (`veteranPools[m]`) of past generations' winning genomes still trading in the
		 * background -- continuous "new money enters an existing market" rather than every
		 * generation getting an isolated, freshly-reset market.
		 *
		 * Partial turnover, gradual weeding (the user's explicit answer -- relaxed limits, not
		 * full-replace-every-gen, not unbounded growth): evicts the worst-performing veterans (by
		 * CURRENT mark-to-market wealth, via `sim.lastPrice()`) down to `veteranCap -
		 * genomesByKey.length` first, so this generation's full batch always fits and the pool
		 * only ever shrinks toward -- never snaps back to -- its cap. Newcomers get freshly-reset
		 * slots ("new money" via `resetAgentLedger`); veterans keep whatever `evolvedDecide`
		 * closure they were wired with when THEY were newcomers -- nothing to re-wire, they just
		 * keep ticking on the SAME persistent sim.
		 *
		 * Scores this generation's z-score within its OWN newcomer cohort only (veterans are
		 * environmental texture/price-impact/competition, not re-scored -- keeps the metric on
		 * the same footing as every other compete path this session, and avoids comparing genomes
		 * that traded over different-length windows). Newcomers who beat their cohort's mean
		 * (z > 0) graduate into `veteranPools[m]` for future generations; the rest are retired to
		 * an inert no-op decide function IMMEDIATELY (not left dangling) -- their slot is then
		 * genuinely free for reuse, never a silently-still-trading orphan invisible to this
		 * function's own eviction bookkeeping.
		 *
		 * The evolved-slot pool per market is capped at `veteranCap + pop` (see this var's own
		 * declaration comment) -- indices beyond that are permanent background archetypes, never
		 * touched here.
		 */
		function competeSequentialTapeFitness(genomesByKey:Array<{key:String, g:StrategyGenome}>, veteranCap:Int, steps:Int, m:Int, initSeed:Int):Map<String, Float> {
			// The whole persistent sim (`competeAgents` slots) is the evolved-slot pool's ceiling --
			// gen 0 alone can carry the WHOLE seeded corpus as newcomers (hundreds of genomes,
			// same as every other compete path here), far more than `veteranCap` alone would
			// suggest, so there's no fixed `veteranCap + something` formula that's safe to
			// pre-check; the free-slot search below throws its own clear error if this ever isn't
			// enough (same "raise --compete-agents" discipline as `competeGenerationFitness`).
			var evolvedPoolSize = competeAgents;
			if (persistentSims[m] == null) {
				var cfg = marketConfigs[m];
				cfg.nAgents = competeAgents;
				cfg.seed = initSeed;
				persistentSims[m] = new MurmurationSim(cfg);
			}
			var sim = persistentSims[m];
			var pop2 = sim.population(); // `pop2` -- this scope's `pop` is the --pop population-size flag
			var vp = veteranPools[m];

			// 1. Evict worst veterans down to make room -- ranked by RECENT (since-last-evaluated)
			// wealth change, not lifetime wealth. Lifetime ranking let a veteran who caught one
			// early move sit permanently at the top of the pool regardless of how stale its edge
			// had since gone or how large a one-directional position it had grown into -- exactly
			// what a net-inventory diagnostic caught live (steadily growing net-long exposure on
			// a persistently trending market). Recent-window ranking means a veteran has to keep
			// earning its slot every generation, not just once.
			var targetVeteranCount = Std.int(Math.max(0, veteranCap - genomesByKey.length));
			var lastPrice = sim.lastPrice();
			if (vp.length > targetVeteranCount) {
				vp.sort((a, b) -> {
					var da = pop2.markToMarket(a.agentId, lastPrice) - a.lastWealth;
					var db = pop2.markToMarket(b.agentId, lastPrice) - b.lastWealth;
					da < db ? 1 : (da > db ? -1 : 0); // descending by recent delta -- worst end up at the tail
				});
				var toEvict = vp.length - targetVeteranCount;
				for (i in 0...toEvict) pop2.setEvolvedAgent(vp[vp.length - 1 - i].agentId, noOpDecide);
				vp = vp.slice(0, targetVeteranCount);
			}
			// Re-baseline every SURVIVING veteran's `lastWealth` to right now, so next
			// generation's eviction again measures just that one window's delta, not a
			// steadily-widening lifetime total.
			for (v in vp) v.lastWealth = pop2.markToMarket(v.agentId, lastPrice);

			// 2. Gather exactly `genomesByKey.length` free slots: any evolved-pool index NOT
			// currently held by a surviving veteran is free (evicted-this-gen, retired-last-gen,
			// or never yet claimed) -- see this function's doc comment for why nothing here is
			// ever left an untracked, silently-still-trading orphan.
			var claimed = new Map<Int, Bool>();
			for (v in vp) claimed.set(v.agentId, true);
			var freeSlots:Array<Int> = [];
			var i = 0;
			while (freeSlots.length < genomesByKey.length) {
				if (i >= evolvedPoolSize)
					throw '--sequential-tape-veterans/--compete-agents too small to fit this generation\'s ${genomesByKey.length} genomes alongside ${vp.length} resident veterans';
				if (!claimed.exists(i)) freeSlots.push(i);
				i++;
			}

			// 3. Wire this generation's newcomers into fresh slots ("new money").
			var steppers = [for (gk in genomesByKey) new GenomeStepper(gk.g)];
			for (k in 0...genomesByKey.length) {
				pop2.resetAgentLedger(freeSlots[k]);
				pop2.setEvolvedAgent(freeSlots[k], steppers[k].decide);
			}

			var startCapital = [for (k in 0...genomesByKey.length) pop2.markToMarket(freeSlots[k], sim.lastPrice())];
			var rows = sim.run(steps);
			var faulted = 0;
			for (s in steppers) if (s.faulted) faulted++;
			if (faulted > 0) Sys.println('  compete[market $m, sequential-tape]: $faulted/${steppers.length} genomes faulted mid-run and stopped trading');
			var finalPrice = rows[rows.length - 1].close;
			// NOTE: an earlier attempt here subtracted each genome's starting capital times the
			// tape's own passive buy-and-hold return, meant to make graduation "market-neutral."
			// It was a NO-OP -- every newcomer in a cohort starts with the SAME fresh capital, so
			// that correction was an IDENTICAL CONSTANT across the whole cohort, and z-scoring is
			// invariant to a shared additive shift (confirmed live: byte-identical output before/
			// after). The live diagnostic's real story was individual RESIDENT veterans accumulating
			// ever-larger one-directional inventory over an unboundedly long residency (see this
			// generation's eviction fix below), not this-generation's newcomer cohort being biased
			// by a shared market drift -- newcomer z-scoring was already fine as plain raw wealth.
			var wealth = [for (k in 0...genomesByKey.length) pop2.markToMarket(freeSlots[k], finalPrice) - startCapital[k]];
			var mean = 0.0;
			for (w in wealth) mean += w;
			mean /= wealth.length;
			var variance = 0.0;
			for (w in wealth) variance += (w - mean) * (w - mean);
			variance /= wealth.length;
			var std = Math.sqrt(variance);
			var zscores = [for (w in wealth) std > 1e-9 ? (w - mean) / std : 0.0];

			if (mapElitesOn) {
				for (k in 0...genomesByKey.length) {
					if (steppers[k].faulted || steppers[k].tradeCount() < 1) continue;
					var desc = MapElites.describeFills(steppers[k].fills(), steps);
					var tradesPerBar = steppers[k].tradeCount() / steps;
					var ck = MapElites.cellKey(tradesPerBar, desc.avgHold, desc.longFrac);
					archive.offer(genomesByKey[k].g, zscores[k], ck, tradesPerBar, desc.avgHold, desc.longFrac);
				}
			}

			// 4. Graduation: newcomers who beat their own cohort's mean become resident veterans;
			// the rest are retired to the no-op decide function right away (see doc comment).
			var graduated = 0;
			for (k in 0...genomesByKey.length) {
				if (zscores[k] > 0) {
					vp.push({agentId: freeSlots[k], genome: genomesByKey[k].g, key: genomesByKey[k].key,
						lastWealth: pop2.markToMarket(freeSlots[k], finalPrice)});
					graduated++;
				} else pop2.setEvolvedAgent(freeSlots[k], noOpDecide);
			}
			// Hard cap, even though step 1's eviction ALREADY made room for this generation's
			// batch: when a single generation routes MORE unique genomes to this market than
			// `veteranCap` itself (step 1 clamps its target to 0, not negative, so it can't evict
			// its way below that), and most of that oversized batch graduates, `vp` can come out
			// of the loop above larger than `veteranCap` -- caught live on a real run (39/30).
			// Trim the worst down to the cap right here so the invariant actually holds.
			if (vp.length > veteranCap) {
				vp.sort((a, b) -> {
					var wa = pop2.markToMarket(a.agentId, finalPrice);
					var wb = pop2.markToMarket(b.agentId, finalPrice);
					wa < wb ? 1 : (wa > wb ? -1 : 0);
				});
				for (i in veteranCap...vp.length) pop2.setEvolvedAgent(vp[i].agentId, noOpDecide);
				vp = vp.slice(0, veteranCap);
			}
			veteranPools[m] = vp;
			// Diagnostic (see this session's "is selection reinforcing the drift" hypothesis):
			// net inventory across every resident evolved slot (veterans + this gen's newcomers,
			// NOT the untouched background archetypes) -- a market whose price is climbing while
			// this stays persistently net-long would confirm the graduation rule (beat-cohort-mean,
			// direction-blind) is selecting for and locking in trend-following genomes, which then
			// mechanically reinforces the very trend that let them graduate.
			var netInv = 0.0;
			for (v in vp) netInv += pop2.inv[v.agentId];
			for (slot in freeSlots) netInv += pop2.inv[slot];
			Sys.println('  sequential-tape[market $m]: veterans ${vp.length}/$veteranCap ($graduated graduated this gen, price=${fmt(finalPrice, 2)}, netInv=${fmt(netInv, 1)})');

			var out = new Map<String, Float>();
			for (k in 0...genomesByKey.length) out.set(genomesByKey[k].key, zscores[k]);
			return out;
		}

		/** Elitism + tournament selection for the `selectors` population, using the SAME
		 * per-generation `fitness` array that drives `popG`'s own evolution (a selector's
		 * "fitness" IS its paired individual's z-score) -- an intentionally simple, INDEPENDENT
		 * step, not threaded through `EvolutionEngine.step`'s return contract (see the plan's own
		 * reasoning: that contract doesn't expose parent-index provenance, and touching it risks
		 * every existing caller). The genome<->selector pairing is therefore only LOOSE after gen
		 * 0 -- both populations evolve under the same selection pressure in parallel, not as
		 * strictly paired parent/child lineages. Acceptable, pre-scoped tradeoff, not a bug. */
		function evolveSelectors(selectorsArr:Array<SymbolSelector>, fitnessArr:Array<Float>, popSize:Int, eliteN:Int, tournamentN:Int, rng:musescript.evo.Rand):Array<SymbolSelector> {
			var ranked = [for (i in 0...selectorsArr.length) {sel: selectorsArr[i], f: fitnessArr[i]}];
			ranked.sort((a, b) -> a.f != b.f ? (a.f < b.f ? 1 : -1) : 0);
			function tournamentPick():SymbolSelector {
				var best = ranked[rng.int(ranked.length)];
				for (_ in 1...tournamentN) {
					var cand = ranked[rng.int(ranked.length)];
					if (cand.f > best.f) best = cand;
				}
				return best.sel;
			}
			var next:Array<SymbolSelector> = [];
			for (i in 0...Std.int(Math.min(eliteN, ranked.length))) next.push(ranked[i].sel);
			while (next.length < popSize) {
				var p1 = tournamentPick();
				var p2 = tournamentPick();
				next.push(SymbolSelector.crossover(p1, p2, rng).mutate(rng, 0.2));
			}
			return next;
		}
		#end

		// P2: the oracle's tape + cache. `attrBars == 0` (or no triage prefix to reuse) means the
		// exact old full-tape-oracle behavior; the default reuses triage's ALREADY-EXISTING short
		// prefix and its own cache file, so a genuinely SHORTER (and separately memoized) backtest
		// answers "which ablation/donor is better" -- a ranking question, not a precision one.
		var attrUseFullTape = (attrBars == 0) || !triageOn;
		var attrTape = attrUseFullTape ? bars : prefixBars;
		var attrCache = attrUseFullTape ? cache : triageCache;
		Sys.println(attrUseFullTape
			? 'attribution oracle: full IS tape (${bars.length} bars) -- --attr-bars 0 or triage disabled'
			: 'attribution oracle: triage prefix (${attrTape.length} bars), same cache triage already warms');

		// Node-ablation-guided mutation/crossover's fitness ORACLE (see Variation.
		// attributedPointMutate/attributedSubtreeCrossover): a real "js" backtest on the SAME
		// in-sample bars evolution is scored against, so the extra evaluations it costs stay
		// honest to the same fitness definition, not a cheaper proxy that could bias search
		// toward something evolution isn't actually selecting on. Routed through the SAME
		// structural-key `cache` the per-generation fitness pass uses (see EvoCache.hx) --
		// baseline/ablation/donor shapes recur constantly across a generation's tournament
		// picks (the same handful of elites get re-ablated on nearly every mutation/crossover
		// call), and this was measured as the dominant cost of a whole generation before being
		// cached (see PLAN_EVO_SPEED.md). Deliberately NO parsimony penalty here (same reasoning
		// as the OOS re-score below): attribution should reflect raw performance, not be
		// deflated by a complexity term that would conflate "this node matters" with "this
		// genome happens to be big."
		var evalFn = function(g:StrategyGenome):Float {
			var key = attrCache.keyFor(g);
			var e = attrCache.get(key);
			if (e == null) {
				var fr = Fitness.evaluate(g, attrTape, "js", false, costBps, startCapital, equityFloor);
				if (fr.ok) {
					var desc = MapElites.describeFills(fr.fills, attrTape.length);
					// Only apply the robustness window when `attrCache` IS the main `cache`
					// (i.e. `attrUseFullTape` -- `--attr-bars 0` or triage disabled): that cache
					// is EXCLUSIVELY shared with the main per-generation pass, which already
					// writes robustness-adjusted sharpe under this session's new default, so
					// this stays consistent with it. The DEFAULT path shares `triageCache`
					// instead with the prefix-triage promote/kill mechanism, which expects a
					// PLAIN prefix sharpe -- writing a robustness-adjusted value there would
					// silently corrupt THAT mechanism's own meaning of the same cache, so this
					// deliberately stays plain in that case (a real, accepted scope limit: the
					// attribution oracle doesn't get the robustness window by default, only the
					// main fitness pass feeding `scoreOf` does).
					var attrSharpe = (fitnessWindows > 1 && attrCache == cache) ? Fitness.robustScore(fr, fitnessWindows, fitnessWindowLambda) : fr.sharpe;
					e = { trades: fr.trades, sharpe: attrSharpe, finalEquity: fr.finalEquity, avgHold: desc.avgHold, longFrac: desc.longFrac, bankrupt: fr.bankrupt };
				} else {
					e = { trades: 0, sharpe: Math.NaN, finalEquity: 0 };
				}
				attrCache.put(key, e);
			}
			return (e.trades >= 1 && !Math.isNaN(e.sharpe) && e.bankrupt != true) ? e.sharpe : Fitness.NEG_INF;
		};

		for (gen in 0...gens) {
			var tGen0 = haxe.Timer.stamp();

			// `--schedule`: this generation's fitness mode, re-derived every iteration (a no-op
			// read when no schedule was given -- `competeOn` just stays pinned to `competeFlag`).
			// A mode SWITCH resets EvolutionEngine's stagnation tracking -- see
			// `resetStagnation()`'s doc comment for why comparing `genBest` across a scale change
			// (real-tape sharpe vs compete z-score) would otherwise corrupt the adaptive
			// mutation-pressure ramp with a signal that's just a scale artifact, not real progress.
			if (scheduleSegments != null) {
				var newCompeteOn = scheduleModeForGen(gen);
				if (newCompeteOn != competeOn) {
					engine.resetStagnation();
					Sys.println('  schedule: switching to ${newCompeteOn ? "compete" : "real"} mode at gen $gen');
				}
				competeOn = newCompeteOn;
				archive = competeOn ? archiveCompete : archiveReal;
			}

			// Bankruptcy difficulty ramp: linearly interpolate capital DOWN / floor UP across the
			// run. `startCapital`/`equityFloor` are plain captured closure vars (same "worker
			// reads the CURRENT generation's data" reference-capture already relied on for
			// `popG`/`keyToIdx` elsewhere in this file) -- reassigning them here is visible to
			// every fbJobQueue worker's next job and to `evalFn` above on its very next call.
			// Whenever the ramp actually MOVES either value, the fitness memo is wiped: a cached
			// eval from a different capital/floor is not a stale-but-usable answer, it's a
			// different backtest entirely (see EvoCache.clear()'s doc comment).
			if (difficultyScheduleOn) {
				var t = gens > 1 ? gen / (gens - 1) : 1.0;
				var newCapital = startCapital + (difficultyEndCapital - startCapital) * t;
				var newFloor = equityFloor + (difficultyEndFloor - equityFloor) * t;
				if (newCapital != startCapital || newFloor != equityFloor) {
					startCapital = newCapital;
					equityFloor = newFloor;
					cache.clear();
					triageCache.clear();
				}
				if (gen == 0 || gen == gens - 1 || gen % 50 == 0)
					Sys.println('  difficulty: capital=${fmt(startCapital, 0)} floor=${fmt(equityFloor, 0)}');
			}

			// Drain whatever the background distillation thread has finished since last
			// generation (zero or more batches, non-blocking) and APPEND (not slot-replace) them
			// to `popG` -- they get evaluated alongside everyone else THIS generation, causing a
			// real, natural population-size bump for exactly one generation. No special trim
			// logic needed: `engine.step` already culls an oversized input back to `--pop`, the
			// same way gen 0's oversized seed population always has.
			if (distillThreadOn) {
				var distilled = distillOutQueue.pop(false);
				var totalDrained = 0;
				while (distilled != null) {
					for (g in distilled) {
						popG.push(g);
						// `selectors` is PARALLEL to `popG` (index i's selector pairs with
						// popG[i], see its own declaration) -- growing `popG` without growing
						// `selectors` in lockstep left a newly-appended index with no selector at
						// all, crashing `competeMultiMarketFitness`'s market-routing lookup with a
						// null dereference the first time `--distill-thread` and
						// `--compete-symbols > 1` ran together. New genomes get a FRESH random
						// selector -- no prior generation's selection pressure to inherit from,
						// same as any other brand-new immigrant.
						#if kestrel
						if (competeSymbols > 1) selectors.push(new SymbolSelector(4, selectorRng));
						#end
					}
					totalDrained += distilled.length;
					distilled = distillOutQueue.pop(false);
				}
				if (totalDrained > 0)
					Sys.println('  distill-thread: drained $totalDrained freshly-synthesized genome(s), popSize temporarily ${popG.length} this gen');
			}

			// Group population indices by structural key so every clone shares ONE evaluation.
			// Elitism + premature convergence mean a handful of unique programs routinely back a
			// whole generation (the corpus-evo runs collapse to clones of one champion by gen 3);
			// keying the work here -- not per index -- is what lets the memo pay off within a
			// single generation, not merely across generations.
			keyToIdx = new Map<String, Array<Int>>(); // reassign the HOISTED slot -- see its declaration's doc comment
			var order:Array<String> = [];
			for (i in 0...popG.length) {
				var key = Canonical.structuralKey(popG[i]);
				if (!keyToIdx.exists(key)) { keyToIdx.set(key, []); order.push(key); }
				keyToIdx.get(key).push(i);
			}

			// Hoisted so the shared post-eval tail (best-tracking, the gen-line print, selection)
			// can read them regardless of which branch below actually populated them --
			// `competeOn`'s branch leaves the WASM/fallback/triage-specific ones at their harmless
			// empty/zero defaults, since none of that machinery runs in competitive mode.
			var fitness:Array<Float>;
			var pendingKeys:Array<String> = [];
			var fallbackMiss:Array<String> = [];
			var triagedOut = 0;
			var triagedOutBySurrogate = 0;
			// Per-symbol sharpe per UNIQUE key, for `--curriculum` (see the end-of-generation weight
			// update below) -- only ever populated for a FRESH (not cache-hit, not triaged-out)
			// full-basket evaluation in the non-compete branch; stays empty in `competeOn` mode, so
			// curriculum's own loop finds nothing and silently no-ops (see this flag's "inert under
			// --compete" doc comment above).
			var perSymbolByKey = new Map<String, Array<Float>>();
			// Raw eval (trades/sharpe/equity) per UNIQUE key: memo hit, native WASM, or JS fallback.
			// Hoisted (like `perSymbolByKey` above) so the shared tail's `--gui` dashboard panel and
			// `--novelty-weight` bonus can read it unconditionally -- both simply see an empty map
			// and no-op under `--compete`, same "inert, not wired" treatment as curriculum/surrogate.
			var evalByKey = new Map<String, CachedEval>();
			if (!competeOn) {
			var missKeys:Array<String> = [];
			for (key in order) {
				var c = cache.get(key);
				if (c != null) evalByKey.set(key, c);
				else missKeys.push(key);
			}

			// Classify each miss key: emit WAT and go native if it compiles without the host_eval
			// escape hatch, else fall back to the JS/interp path. Genomes needing host_eval (any of
			// the 400+ `ta` registry indicators beyond the ~14 StrategyWasmEmitter lowers natively)
			// aren't representable on GraalWasmHost, which has no interp callback wired for it --
			// they still get a REAL, correct evaluation, just not GraalWasm-accelerated, so
			// selection is never silently biased against a newer Wickra-ported indicator.
			// `pendingKeys`/`fallbackMiss` themselves are the HOISTED slots (see above the
			// `if (!competeOn)` split) -- not redeclared here, just reused, so the shared tail's
			// gen-line print sees this generation's real counts instead of a shadowed empty copy.
			var stringsPending = new Map<String, Array<String>>();
			var wasmMiss:Array<String> = [];
			var unsupported = 0;
			for (key in missKeys) {
				var g = popG[keyToIdx.get(key)[0]];
				// `--equity-floor`'s bankruptcy kill-switch only exists in OrderSim.hx (the
				// JS/interp fallback path) -- the native-WASM backend is a separately compiled WAT
				// engine that doesn't check it. Force every genome down fallback rather than
				// silently letting WASM-routed genomes skip the solvency gate.
				if (forceFallback) { fallbackMiss.push(key); continue; }
				if (moduleCache.exists(key)) { wasmMiss.push(key); continue; }
				if (unsupportedKeys.exists(key)) { fallbackMiss.push(key); unsupported++; continue; }
				var emitted = emitGenome(g);
				if (emitted == null || StringTools.contains(emitted.wat, "call $host_eval")) {
					unsupportedKeys.set(key, true);
					unsupported++;
					fallbackMiss.push(key);
					continue;
				}
				sys.io.File.saveContent('$watDir/$key.wat', emitted.wat);
				stringsPending.set(key, emitted.strings);
				pendingKeys.push(key);
				wasmMiss.push(key);
			}
			if (pendingKeys.length > 0) {
				var py = Sys.systemName() == "Windows" ? ".venv/Scripts/python.exe" : ".venv/bin/python";
				var code = Sys.command(py, ["tools/wat2wasm_batch.py", watDir]);
				if (code != 0) throw "wat2wasm batch failed";
			}
			for (key in pendingKeys) moduleCache.set(key, {strings: stringsPending.get(key), wasmPath: '$watDir/$key.wasm'});

			// Dispatch native-WASM miss keys to the worker pool -- one job per UNIQUE key.
			var dispatched = 0;
			for (key in wasmMiss) {
				var entry = moduleCache.get(key);
				jobQueue.add({key: key, wasmPath: entry.wasmPath, strings: entry.strings, stop: false});
				dispatched++;
			}
			for (_ in 0...dispatched) {
				var r = resultQueue.pop(true);
				var e:CachedEval = {trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity,
					avgHold: r.avgHold, longFrac: r.longFrac};
				evalByKey.set(r.key, e);
				cache.put(r.key, e);
				if (r.perSymbolSharpe.length > 0) perSymbolByKey.set(r.key, r.perSymbolSharpe);
				if (surrogateOn) surrogate.update(Canonical.shapeFeatures(popG[keyToIdx.get(r.key)[0]]), surrogateTarget(e));
			}
			// JS/interp fallback -- worker-pooled (see the fbJobQueue/fbResultQueue pool set up
			// above; P3 in PLAN_EVO_SPEED.md). Surrogate pre-filter (if on) runs first -- a zero-cost
			// structural guess that skips the CLEAREST duds before they even reach a prefix-tape
			// backtest; prefix triage then gates whatever survives that further, same as before.
			if (surrogateOn && fallbackMiss.length > 1) {
				var surrScored = [for (key in fallbackMiss) {key: key, s: surrogate.predict(Canonical.shapeFeatures(popG[keyToIdx.get(key)[0]]))}];
				surrScored.sort((a, b) -> a.s < b.s ? 1 : (a.s > b.s ? -1 : 0));
				var surrKeep = Std.int(Math.ceil(surrScored.length * surrogateKeep));
				if (surrKeep < 1) surrKeep = 1;
				var keptKeys = new Map<String, Bool>();
				for (i in 0...surrKeep) keptKeys.set(surrScored[i].key, true);
				// Gen-local NEG_INF only -- same "not written to the real memo" discipline as
				// triage's own kill list just below: the surrogate is a proxy too, so a genome it
				// under-rates must stay eligible for a real eval if it recurs.
				for (i in surrKeep...surrScored.length) evalByKey.set(surrScored[i].key, {trades: 0, sharpe: Math.NaN, finalEquity: 0});
				fallbackMiss = [for (key in fallbackMiss) if (keptKeys.exists(key)) key];
				triagedOutBySurrogate = surrScored.length - surrKeep;
			}
			// Prefix triage gates it further: score every NEW fallback genome on a cheap prefix
			// first, promote only the top fraction to the full-tape eval, kill the rest for this
			// generation.
			var promoted = fallbackMiss;
			if (triageOn && fallbackMiss.length > 1) {
				var scored:Array<{key:String, s:Float}> = [];
				var prefixMiss:Array<String> = [];
				for (key in fallbackMiss) {
					var pc = triageCache.get(key);
					if (pc != null) scored.push({key: key, s: (pc.trades >= 1 && !Math.isNaN(pc.sharpe) && pc.bankrupt != true) ? pc.sharpe : Fitness.NEG_INF});
					else prefixMiss.push(key);
				}
				for (key in prefixMiss) fbJobQueue.add({key: key, useFullTape: false, stop: false});
				for (_ in 0...prefixMiss.length) {
					var r = fbResultQueue.pop(true);
					var pc:CachedEval = r.ok ? {trades: r.trades, sharpe: r.sharpe, finalEquity: r.equity, bankrupt: r.bankrupt} : {trades: 0, sharpe: Math.NaN, finalEquity: 0};
					triageCache.put(r.key, pc);
					scored.push({key: r.key, s: (pc.trades >= 1 && !Math.isNaN(pc.sharpe) && pc.bankrupt != true) ? pc.sharpe : Fitness.NEG_INF});
				}
				scored.sort((a, b) -> a.s < b.s ? 1 : (a.s > b.s ? -1 : 0));
				var keep = Std.int(Math.ceil(scored.length * triageKeep));
				if (keep < 1) keep = 1;
				promoted = [for (i in 0...keep) scored[i].key];
				// Killed keys: gen-local NEG_INF via a dead eval record, deliberately NOT written
				// to the full memo -- triage is a proxy, so a genome it under-rates must stay
				// eligible for a real full eval if it ever reaches a backend that doesn't triage.
				for (i in keep...scored.length) evalByKey.set(scored[i].key, {trades: 0, sharpe: Math.NaN, finalEquity: 0});
				triagedOut = scored.length - keep;
			}
			for (key in promoted) fbJobQueue.add({key: key, useFullTape: true, stop: false});
			for (_ in 0...promoted.length) {
				var r = fbResultQueue.pop(true);
				var e:CachedEval;
				if (r.ok) {
					var desc = MapElites.describeFills(r.fills, bars.length);
					e = {trades: r.trades, sharpe: r.sharpe, finalEquity: r.equity,
						avgHold: desc.avgHold, longFrac: desc.longFrac, bankrupt: r.bankrupt};
				} else {
					e = {trades: 0, sharpe: Math.NaN, finalEquity: 0};
				}
				evalByKey.set(r.key, e);
				cache.put(r.key, e);
				if (r.perSymbolSharpe.length > 0) perSymbolByKey.set(r.key, r.perSymbolSharpe);
				if (surrogateOn) surrogate.update(Canonical.shapeFeatures(popG[keyToIdx.get(r.key)[0]]), surrogateTarget(e));
			}

			// Score: fan each key's raw eval out to every index sharing it, applying the soft-cap
			// parsimony penalty per genome. nodeCount is identical across a shared key, but reading
			// it per index keeps this robust if that invariant ever changes.
			fitness = [for (_ in popG) Fitness.NEG_INF];
			for (key in order) {
				var e = evalByKey.get(key);
				var idxs = keyToIdx.get(key);
				for (idx in idxs) fitness[idx] = scoreOf(e, Canonical.nodeCount(popG[idx]));
				// MAP-Elites: offer this genome into its behavioral cell -- BEFORE parsimony, using
				// the raw eval directly (same reasoning as the OOS re-score / attribution evalFn:
				// niching should be driven by what the strategy actually did, not deflated by a
				// complexity penalty that would make a legitimately larger-but-still-novel genome
				// lose its niche slot to a smaller one that behaves identically). The
				// parsimony-adjusted `fitness` is deliberately NOT what's compared here.
				if (mapElitesOn && e != null && e.trades >= 1 && !Math.isNaN(e.sharpe)) {
					var tradesPerBar = e.trades / bars.length;
					var avgHold = e.avgHold != null ? e.avgHold : 0.0;
					var longFrac = e.longFrac != null ? e.longFrac : 0.5;
					var ck = MapElites.cellKey(tradesPerBar, avgHold, longFrac);
					archive.offer(popG[idxs[0]], e.sharpe, ck, tradesPerBar, avgHold, longFrac);
				}
			}
			} else {
				#if kestrel
				if (sequentialTapeOn && competeSymbols > 1) {
					// Same per-individual market routing as `competeMultiMarketFitness` (selectors
					// can differ between individuals sharing a genome, so this stays per-index, not
					// deduped by structural key) -- but each market group is scored by the
					// PERSISTENT `competeSequentialTapeFitness` instead of a fresh-sim-per-call.
					var chosenMarket = [for (idx in 0...popG.length) {
						var bestM = 0;
						var bestScore = selectors[idx].score(marketFeatures[0]);
						for (mkt in 1...marketFeatures.length) {
							var s = selectors[idx].score(marketFeatures[mkt]);
							if (s > bestScore) { bestScore = s; bestM = mkt; }
						}
						bestM;
					}];
					fitness = [for (_ in popG) Fitness.NEG_INF];
					var marketCounts = [for (_ in marketConfigs) 0];
					for (mkt in 0...marketConfigs.length) {
						var groupIdx = [for (idx in 0...popG.length) if (chosenMarket[idx] == mkt) idx];
						marketCounts[mkt] = groupIdx.length;
						if (groupIdx.length == 0) continue;
						var genomesByKey = [for (idx in groupIdx) {key: 'pop_$idx', g: popG[idx]}];
						var zscores = competeSequentialTapeFitness(genomesByKey, sequentialTapeVeterans, simSteps, mkt, simSeed);
						for (idx in groupIdx) fitness[idx] = zscores.get('pop_$idx');
					}
					Sys.println('  markets chosen: ' + [for (mkt in 0...marketConfigs.length) '#$mkt=${marketCounts[mkt]}'].join(" "));
				} else if (sequentialTapeOn) {
					var genomesByKey = [for (key in order) {key: key, g: popG[keyToIdx.get(key)[0]]}];
					var zscores = competeSequentialTapeFitness(genomesByKey, sequentialTapeVeterans, simSteps, 0, simSeed);
					fitness = [for (_ in popG) Fitness.NEG_INF];
					for (key in order) {
						var z = zscores.get(key);
						var idxs = keyToIdx.get(key);
						for (idx in idxs) fitness[idx] = z;
					}
				} else if (competeSymbols > 1) {
					fitness = competeMultiMarketFitness(popG, selectors, marketConfigs, marketFeatures, competeAgents, simSteps, simSeed + gen);
				} else {
					var genomesByKey = [for (key in order) {key: key, g: popG[keyToIdx.get(key)[0]]}];
					var zscores = competeGenerationFitness(genomesByKey, competeAgents, simSteps, simSeed + gen);
					fitness = [for (_ in popG) Fitness.NEG_INF];
					for (key in order) {
						var z = zscores.get(key);
						var idxs = keyToIdx.get(key);
						for (idx in idxs) fitness[idx] = z;
					}
				}
				#else
				fitness = [for (_ in popG) Fitness.NEG_INF]; // unreachable -- competeOn already threw at startup on a non-kestrel build
				#end
			}

			var genBest = Fitness.NEG_INF;
			var bestIdx = 0;
			var validN = 0;
			var sum = 0.0;
			for (i in 0...fitness.length) {
				if (fitness[i] == Fitness.NEG_INF) continue;
				validN++;
				sum += fitness[i];
				if (fitness[i] > genBest) { genBest = fitness[i]; bestIdx = i; }
			}
			// Per-mode champion tracking (see `--schedule`'s doc comment) -- `currentBest`/
			// `currentBestGenome` below are just a same-generation READ alias for whichever
			// mode is active, so the gen-line print/dashboard don't need their own branching.
			if (competeOn) { if (genBest > bestCompete) { bestCompete = genBest; bestGenomeCompete = popG[bestIdx]; } }
			else { if (genBest > bestReal) { bestReal = genBest; bestGenomeReal = popG[bestIdx]; } }
			var currentBest = competeOn ? bestCompete : bestReal;
			var currentBestGenome = competeOn ? bestGenomeCompete : bestGenomeReal;
			var mean = validN > 0 ? sum / validN : 0.0;
			var genMs = (haxe.Timer.stamp() - tGen0) * 1000;
			// `champion="name"` alone is misleading over a long run: `Variation.hx`'s
			// crossover/mutate both copy `name: g.name` from parent to child UNCONDITIONALLY, so
			// every descendant of an early strong seed keeps that seed's ORIGINAL display name
			// forever, no matter how many generations of structural change separate them from it.
			// A `key=` short structural-hash prefix alongside the name (see `Canonical.
			// structuralKey`, already used as the archive/cache key everywhere else) makes an
			// actual lineage change visible at a glance even when the name doesn't change -- the
			// name staying fixed for 100+ generations is NOT proof the same tree has been
			// champion the whole time; the key changing (or not) is the real tell.
			var championKey = currentBestGenome != null ? Canonical.structuralKey(currentBestGenome).substr(0, 8) : "?";
			Sys.println('gen ${pad(Std.string(gen), 2)} | popSize=${popG.length} uniq=${order.length} new=${pendingKeys.length} fallback=${fallbackMiss.length}'
				+ (surrogateOn ? ' surrogateSkipped=$triagedOutBySurrogate' : '') + ' triaged=$triagedOut valid=$validN niches=${archive.size()}'
				+ ' | best=${fmt(genBest, 4)} mean=${fmt(mean, 4)} champion="${currentBestGenome != null ? currentBestGenome.name : "?"}" key=$championKey'
				+ ' | ${fmt(genMs, 0)}ms');

			if (dashboard != null) {
				var validFitness = [for (f in fitness) if (f != Fitness.NEG_INF) f];
				var nicheSummary = archive.summary();
				// Raw (pre-parsimony) Sharpe per UNIQUE genome this generation -- directly
				// comparable to the buy-and-hold benchmark's own raw Sharpe, one point per
				// distinct program rather than fanned out across clone slots.
				var isPerf = [for (key in order) if (evalByKey.get(key) != null
					&& evalByKey.get(key).trades >= 1 && !Math.isNaN(evalByKey.get(key).sharpe)) evalByKey.get(key).sharpe];
				// OOS re-sampled only every `guiOosEvery` generations (see its doc comment) --
				// null on the skipped generations, so the panel keeps showing the last real
				// sample instead of a misleadingly-empty one.
				var oosPerf:Null<Array<Float>> = null;
				if (gen % guiOosEvery == 0 || gen == gens - 1) {
					oosPerf = [];
					for (key in order) {
						var g = popG[keyToIdx.get(key)[0]];
						var oosr = Fitness.evaluate(g, oosBars, "js", false, costBps, startCapital, equityFloor);
						if (oosr.ok && oosr.trades >= 1 && !Math.isNaN(oosr.sharpe) && !oosr.bankrupt) oosPerf.push(oosr.sharpe);
					}
				}
				dashboard.update(gen, genBest, mean, archive.size(), currentBestGenome != null ? currentBestGenome.name : "?",
					validFitness, [for (c in nicheSummary) c.key], [for (c in nicheSummary) c.fitness],
					isPerf, oosPerf, isBenchmark, oosBenchmark);
			}

			// Pause/resume lives on the dashboard (its Pause button, always the primary window);
			// HumanLoopWindow is purely the population-browser+editor that comes to front once
			// there's actually something paused to intervene on.
			if (dashboard != null && dashboard.isPaused()) {
				if (humanLoop != null) {
					humanLoop.setPopulation(popG, fitness);
					humanLoop.show();
				}
				Sys.println('[paused] after generation $gen -- click Resume in the dashboard to continue');
				dashboard.waitForResume();
			} else if (humanLoop != null) {
				humanLoop.setPopulation(popG, fitness);
			}

			if (competeOn) lastFitnessCompete = fitness; else lastFitnessReal = fitness;
			if (curriculumOn && isBasket.length > 1) {
				// Adversarial curriculum: this generation's per-symbol mean sharpe (across
				// whatever genomes got a FRESH full-basket eval this generation -- see
				// `perSymbolByKey`'s doc comment) drives NEXT generation's basket-mean weighting,
				// via a softmax over -mean/temp so symbols the population is currently WORST at
				// get weighted up. Mutated IN PLACE (never reassigned) -- see `curriculumWeights`'s
				// declaration for why that matters for the WASM worker pool's plain-parameter
				// reference to see the update.
				var symbolSum = [for (_ in isBasket) 0.0];
				var symbolCount = [for (_ in isBasket) 0];
				for (key in order) {
					var arr = perSymbolByKey.get(key);
					if (arr == null) continue;
					for (i in 0...arr.length) if (!Math.isNaN(arr[i])) { symbolSum[i] += arr[i]; symbolCount[i]++; }
				}
				var symbolMean = [for (i in 0...isBasket.length) symbolCount[i] > 0 ? symbolSum[i] / symbolCount[i] : 0.0];
				var expVals = [for (m in symbolMean) Math.exp(-m / curriculumTemp)];
				var expSum = 0.0;
				for (v in expVals) expSum += v;
				for (i in 0...curriculumWeights.length)
					curriculumWeights[i] = expSum > 0 ? (expVals[i] / expSum) * isBasket.length : 1.0;
				Sys.println('  curriculum weights: [${[for (w in curriculumWeights) fmt(w, 2)].join(", ")}] (mean sharpe: [${[for (m in symbolMean) fmt(m, 3)].join(", ")}])');
			}
			if (gen < gens - 1) {
				// Speciation (structural fitness-sharing) + novelty (behavioral archive-distance
				// bonus) ONLY adjust SELECTION pressure -- `best`/`bestGenome`/MAP-Elites offering
				// above already ran off raw `fitness` and are untouched. Both off by default
				// (`selectionFitness == fitness`, the exact same array) -- see this session's
				// neuroevolution-inspired-upgrades plan.
				var selectionFitness = fitness;
				if (speciationOn || noveltyWeight != 0.0) {
					selectionFitness = fitness.copy();
					if (speciationOn) {
						var sigByKey = new Map<String, Map<String, Int>>();
						for (key in order) sigByKey.set(key, Canonical.shapeSignature(popG[keyToIdx.get(key)[0]]));
						var reps:Array<{sig:Map<String, Int>, keys:Array<String>}> = [];
						for (key in order) {
							var sig = sigByKey.get(key);
							var found = false;
							for (sp in reps) {
								if (Canonical.shapeDistance(sig, sp.sig) <= speciationThreshold) {
									sp.keys.push(key);
									found = true;
									break;
								}
							}
							if (!found) reps.push({sig: sig, keys: [key]});
						}
						for (sp in reps) {
							var memberCount = 0;
							for (key in sp.keys) memberCount += keyToIdx.get(key).length;
							if (memberCount <= 1) continue;
							var penalty = speciationLambda * Math.log(memberCount);
							for (key in sp.keys)
								for (idx in keyToIdx.get(key))
									if (selectionFitness[idx] != Fitness.NEG_INF) selectionFitness[idx] -= penalty;
						}
						Sys.println('  species: ${reps.length} distinct (threshold=$speciationThreshold)');
					}
					if (noveltyWeight != 0.0 && mapElitesOn) {
						for (key in order) {
							var e = evalByKey.get(key);
							if (e == null || e.trades < 1 || Math.isNaN(e.sharpe)) continue;
							var tradesPerBar = e.trades / bars.length;
							var avgHold = e.avgHold != null ? e.avgHold : 0.0;
							var longFrac = e.longFrac != null ? e.longFrac : 0.5;
							var novelty = archive.noveltyDistance(tradesPerBar, avgHold, longFrac);
							for (idx in keyToIdx.get(key))
								if (selectionFitness[idx] != Fitness.NEG_INF) selectionFitness[idx] += noveltyWeight * novelty;
						}
					}
				}
				popG = engine.step(popG, selectionFitness, evalFn, attrCrossProb, donorCap, esNudgeProb);
				#if kestrel
				// Co-evolve the `selectors` population alongside `popG`, under the SAME
				// selection-pressure array -- see `evolveSelectors`'s own doc comment for why the
				// genome<->selector pairing is only LOOSE (not genealogically exact) after gen 0.
				if (competeSymbols > 1)
					selectors = evolveSelectors(selectors, selectionFitness, pop, engine.elite, 3, selectorRng);
				#end
				if (mapElitesOn && immigrantRate > 0)
					popG = injectArchiveDiversity(popG, archive, engine.elite, immigrantRate, immigrantRng);
				// Rare merger event -- see `mergerEvent`'s own doc comment. `evalBatch` differs by
				// mode: real-tape sharpe is independent per-genome (plain `evalFn` map); compete
				// z-score needs a shared cohort to be meaningful, so ALL candidate hybrids from
				// every pairwise recombination are wired into ONE `competeGenerationFitness` call
				// together (a mini cohort of hybrids competing against each other).
				if (mapElitesOn && mergerRate > 0 && mergerRng.float() < mergerRate) {
					var evalBatch:Array<StrategyGenome>->Array<Float> = hs -> [for (h in hs) evalFn(h)];
					#if kestrel
					if (competeOn) evalBatch = hs -> {
						var genomesByKey = [for (i in 0...hs.length) {key: 'merger_$i', g: hs[i]}];
						var res = competeGenerationFitness(genomesByKey, Std.int(Math.max(competeAgents, hs.length)), simSteps, seed * 1000003 + gen);
						[for (gk in genomesByKey) res.get(gk.key)];
					};
					#end
					var merged = mergerEvent([archiveReal, archiveCompete], mergerK, evalBatch, mergerVariation);
					if (merged != null) {
						popG = injectMergerClones(popG, merged.hybrid, mergerInject, engine.elite, mergerVariation, mergerRng);
						Sys.println('  merger: gen ${gen + 1} -- sources [${merged.sourceKeys.join(", ")}] (parent fitness ${[for (f in merged.parentFitness) fmt(f, 3)].join(" / ")}) -> hybrid fitness ${fmt(merged.fitness, 3)}, $mergerInject clone(s) injected');
					}
				}
				if (distillEvery > 0 && (gen + 1) % distillEvery == 0)
					popG = distillReinject(popG, [archiveReal, archiveCompete], distillK, engine.elite, isBasket, costBps, startCapital, equityFloor, distillRng);
				// Splice any human-edited/-selected genomes (queued via HumanLoopWindow's "Apply
				// Edit" button) into the tail of the FRESH population `engine.step` just produced --
				// starting from the end so elitism's leading slots (`engine.elite`, always < popSize)
				// are never overwritten by a human contribution that hasn't proven itself yet. Empty
				// on every generation nobody clicked Apply -- a plain no-op.
				if (humanLoop != null) {
					var injected = humanLoop.drainInjections();
					if (injected.length > 0) {
						var startIdx = Std.int(Math.max(engine.elite, popG.length - injected.length));
						for (i in 0...injected.length) {
							var slot = startIdx + i;
							if (slot < popG.length) popG[slot] = injected[i];
						}
						Sys.println('[human-loop] injected ${injected.length} genome(s) into generation ${gen + 1}');
					}
				}
			}
		}
		var totalS = haxe.Timer.stamp() - totalT0;

		for (_ in 0...threads) jobQueue.add({key: "", wasmPath: "", strings: [], stop: true});
		for (_ in 0...threads) ackQueue.pop(true);
		for (_ in 0...Std.int(Math.max(1, threads))) fbJobQueue.add({key: "", useFullTape: false, stop: true});
		// No ack queue needed here either -- same reasoning as the fallback pool just above:
		// nothing after this point reads `distillOutQueue` again, so a fire-and-forget stop
		// sentinel is enough (the thread checks it between micro-search cycles, not mid-cycle,
		// so shutdown isn't instant, but nothing blocks waiting on it).
		if (distillThreadOn) distillStopQueue.add({stop: true});

		// Per-mode champion + MAP-Elites report (see `--schedule`'s doc comment for why a real-tape
		// sharpe and a compete z-score can't share one report/one archive). Called ONCE (today's
		// exact behavior, whichever mode the static `--compete` flag picked) or TWICE (once per
		// mode, when `--schedule` actually alternated between them this run).
		function printChampionAndMapElites(isCompeteMode:Bool, best:Float, bestGenome:StrategyGenome, arch:EliteArchive):Void {
			var modeLabel = isCompeteMode ? "COMPETE" : "REAL";
			Sys.println('\n=== $modeLabel CHAMPION (fitness=${fmt(best, 4)}, lineage=${bestGenome != null ? bestGenome.lineage.join(" <- ") : "?"}) ===');
			if (bestGenome != null && !isCompeteMode) {
				var champKey = Canonical.structuralKey(bestGenome);
				// Printed trades/equity/sharpe are the BASKET AGGREGATE (see BasketFitness.
				// aggregateBasket) -- the same numbers that actually produced `fitness=` above, not
				// just symbol 0's individual result, which would be inconsistent with it in basket
				// mode. The determinism check itself stays scoped to symbol 0 (`bars`) -- verifying
				// determinism once is enough, no need to re-verify it per symbol.
				if (moduleCache.exists(champKey)) {
					var champEntry = moduleCache.get(champKey);
					var champInst = host.instantiate(host.loadModuleFile(champEntry.wasmPath), champEntry.strings);
					var a = champInst.run(bars, new Map());
					var b = champInst.run(bars, new Map());
					if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
						throw "champion non-deterministic";
					var perSymbol = [{trades: a.trades, sharpe: a.sharpe, finalEquity: a.finalEquity}];
					for (i in 1...isBasket.length) {
						var r = champInst.run(isBasket[i], new Map());
						perSymbol.push({trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity});
					}
					var agg = BasketFitness.aggregateBasket(perSymbol);
					Sys.println('backend=wasm trades=${agg.trades} equity=${fmt(agg.finalEquity, 2)} sharpe=${fmt(agg.sharpe, 4)} nodeCount=${Canonical.nodeCount(bestGenome)}' + (isBasket.length > 1 ? ' (aggregated across ${isBasket.length} symbols)' : ''));
				} else {
					// Champion needed the JS/interp fallback (see jsFallback above) -- no WASM
					// module exists for it, so verify determinism the same way, on that backend.
					var a = Fitness.evaluate(bestGenome, bars, "js", false, costBps, startCapital, equityFloor);
					var b = Fitness.evaluate(bestGenome, bars, "js", false, costBps, startCapital, equityFloor);
					if (a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-9)
						throw "champion non-deterministic";
					if (equityFloor > 0 && a.bankrupt) Sys.println('WARNING: reported champion crossed --equity-floor $equityFloor on the IS tape');
					var perSymbol = [{trades: a.trades, sharpe: a.sharpe, finalEquity: a.finalEquity}];
					for (i in 1...isBasket.length) {
						var r = Fitness.evaluate(bestGenome, isBasket[i], "js", false, costBps, startCapital, equityFloor);
						perSymbol.push({trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity});
					}
					var agg = BasketFitness.aggregateBasket(perSymbol);
					Sys.println('backend=js(fallback) trades=${agg.trades} equity=${fmt(agg.finalEquity, 2)} sharpe=${fmt(agg.sharpe, 4)} nodeCount=${Canonical.nodeCount(bestGenome)}' + (isBasket.length > 1 ? ' (aggregated across ${isBasket.length} symbols)' : ''));
				}
				Sys.println(Expand.expand(bestGenome));
			} else if (bestGenome != null) {
				// `--compete`: `fitness=` above is a Z-SCORE (mark-to-market wealth relative to that
				// generation's cohort), not a sharpe -- re-running it against the nominal `bars` tape
				// via Fitness.evaluate/WASM would be comparing it to a number it was never scored
				// against. Just print the source here; the fresh-market re-check below (replacing the
				// tape-based OOS re-score) is this mode's actual "did it generalize" evidence.
				Sys.println('(--compete mode: fitness is a cohort-relative z-score, not a sharpe -- see the fresh-market re-check below)');
				Sys.println(Expand.expand(bestGenome));
			}
			if (mapElitesOn) {
				var cells = arch.summary();
				Sys.println('\n=== $modeLabel MAP-Elites diversity: ${cells.length}/48 behavioral cells occupied (tradeFreq_hold_bias) ===');
				for (c in cells) Sys.println('  ${c.key}: fitness=${fmt(c.fitness, 4)}');
				// `--save-elites`: one runnable .ms file per occupied cell, so every distinct
				// behavioral niche's champion survives past this one run's console output -- a
				// low-turnover mean-reverter, a scalper, a long-only trend-follower, etc. can all be
				// picked back up individually (as a `--tapes`-basket seed via CorpusSeed, or just read
				// by hand) instead of only the single overall best genome being kept anywhere.
				// Filename prefixed by mode (real_/compete_) so a `--schedule` run's two archives
				// never collide writing the same cell key to the same directory.
				if (saveElites) {
					if (!sys.FileSystem.exists(elitesDir)) sys.FileSystem.createDirectory(elitesDir);
					var prefix = isCompeteMode ? "compete_" : "real_";
					for (e in arch.entries()) {
						var header = '/* MAP-Elites cell ${e.key} ($modeLabel, tradeFreq_hold_bias) -- fitness=${fmt(e.cell.fitness, 4)}\n'
							+ '   tradesPerBar=${fmt(e.cell.tradesPerBar, 4)} avgHold=${fmt(e.cell.avgHold, 2)} longFrac=${fmt(e.cell.longFrac, 2)}\n'
							+ '   lineage: ${e.cell.genome.lineage != null ? e.cell.genome.lineage.join(" <- ") : "?"}\n'
							+ '   from a corpus-evo run seeded from the same corpus/indicator set, seed=$seed */\n';
						sys.io.File.saveContent('$elitesDir/$prefix${e.key}.ms', header + Expand.expand(e.cell.genome));
					}
					Sys.println('saved ${cells.length} elite genomes to $elitesDir/ (prefix "$prefix")');
				}
			}
		}
		if (scheduleSegments != null) {
			printChampionAndMapElites(false, bestReal, bestGenomeReal, archiveReal);
			printChampionAndMapElites(true, bestCompete, bestGenomeCompete, archiveCompete);
		} else if (competeFlag) {
			printChampionAndMapElites(true, bestCompete, bestGenomeCompete, archiveCompete);
		} else {
			printChampionAndMapElites(false, bestReal, bestGenomeReal, archiveReal);
		}
		Sys.println('total wall: ${fmt(totalS, 1)}s  modules compiled: ${count(moduleCache)}');
		if (cachePath != null)
			Sys.println('cache: ${cache.hits} hits / ${cache.misses} misses across the run, ${cache.size()} unique programs memoized');
		if (tunerOn) {
			Sys.println('\n=== growth tuner: learned node-type weights ===');
			for (cat in ["boolTerm", "boolRecurse", "riskExit", "multiOutput", "scalarTerm", "scalarRecurse"]) {
				var s = tuner.summary(cat);
				Sys.println('  $cat: ' + [for (e in s) '${e.tag}=${fmt(e.weight * 100, 1)}%'].join(" "));
			}
			if (tunerPath != null) { tuner.save(tunerPath); Sys.println('  saved to $tunerPath'); }
		}

		if (surrogateOn) {
			Sys.println('surrogate model: ${surrogate.samplesSeen} training samples seen this run');
			if (surrogatePath != null) { surrogate.save(surrogatePath); Sys.println('  saved to $surrogatePath'); }
		}

		// --- walk-forward OOS re-score: the top-K genomes by IS fitness, re-scored on the
		// held-out tail the evolution loop never saw. "Held" = still trading with a positive
		// Sharpe out of sample; "did NOT hold" is reported just as plainly, matching the
		// project's own walk-forward evidence discipline -- not everything IS-strong survives
		// contact with data it was never fit on, and that's the whole point of checking.
		function printRealHoldout(lastFit:Array<Float>):Void {
			Sys.println('\n=== OOS RE-SCORE (top 10 by IS fitness, held-out ${oosBars.length}-bar tail' + (oosBasket.length > 1 ? ', aggregated across ${oosBasket.length} symbols' : '') + ') ===');
			var ranked = [for (i in 0...popG.length) {g: popG[i], isFit: lastFit[i]}];
			ranked.sort((a, b) -> a.isFit != b.isFit ? (a.isFit < b.isFit ? 1 : -1) : 0);
			var seen = new Map<String, Bool>();
			var shown = 0;
			var held = 0, checked = 0;
			for (r in ranked) {
				if (shown >= 10) break;
				if (r.isFit == Fitness.NEG_INF) break;
				var key = Canonical.structuralKey(r.g);
				if (seen.exists(key)) continue; // elitism duplicates the same genome across slots
				seen.set(key, true);
				shown++;
				// Aggregated across the WHOLE oos basket (cheap: only the top 10 genomes, unlike the
				// per-generation eval loop which stays scoped to basket[0] for speed) -- see
				// BasketFitness.aggregateBasket. Degenerates to exactly the old single-symbol
				// Fitness.score(oos, 1) behavior when oosBasket has one element.
				var anyErr = false;
				var anyBankrupt = false;
				var perSymbol:Array<{trades:Int, sharpe:Float, finalEquity:Float}> = [];
				for (sym in oosBasket) {
					var fr = Fitness.evaluate(r.g, sym, "js", false, costBps, startCapital, equityFloor);
					if (!fr.ok) { anyErr = true; break; }
					if (fr.bankrupt) anyBankrupt = true;
					perSymbol.push({trades: fr.trades, sharpe: fr.sharpe, finalEquity: fr.finalEquity});
				}
				checked++;
				var agg = anyErr ? {trades: 0, sharpe: Math.NaN, finalEquity: 0.0} : BasketFitness.aggregateBasket(perSymbol);
				// The honesty firewall applies HERE too: a genome that only stayed solvent in-sample
				// but goes bust on the untouched OOS holdout must not read as "held" just because its
				// raw sharpe happens to be positive.
				var oosScore = (agg.trades >= 1 && !Math.isNaN(agg.sharpe) && !anyBankrupt) ? agg.sharpe : Fitness.NEG_INF;
				var holdMark = oosScore > 0 ? "HELD" : "did not hold";
				if (oosScore > 0) held++;
				Sys.println('  ${pad(Std.string(shown), 2)}. IS=${fmt(r.isFit, 4)}  OOS=${!anyErr ? fmt(oosScore, 4) : "n/a"} (trades=${agg.trades})  [$holdMark]  ${r.g.name}');
			}
			Sys.println('OOS summary: ${held}/${checked} of the top IS performers held a positive Sharpe out of sample.');
		}
		#if kestrel
		// --- compete fresh-market re-check: NOT a real-tape holdout (that's Phase 3's honesty
		// firewall item, not implemented here) -- the top-10 genomes by final-generation
		// cohort z-score, dropped into a BRAND NEW shared MurmurationSim with a seed never used
		// during evolution (so it's at least a fresh random background population/price path,
		// not the exact market any generation was fit against), re-ranked among THEMSELVES.
		// "Held" = still finished positive (above the fresh cohort's own mean) in that fresh
		// market, same "don't just trust the training-time number" spirit as the tape-based
		// OOS check above, just without a fixed historical holdout to check it against.
		function printCompeteHoldout(lastFit:Array<Float>):Void {
			Sys.println('\n=== COMPETE FRESH-MARKET RE-CHECK (top 10 by final z-score, seed never used during evolution -- NOT a real-tape holdout) ===');
			var ranked = [for (i in 0...popG.length) {g: popG[i], isFit: lastFit[i]}];
			ranked.sort((a, b) -> a.isFit != b.isFit ? (a.isFit < b.isFit ? 1 : -1) : 0);
			var seen = new Map<String, Bool>();
			var topKey:Array<String> = [];
			var topFit = new Map<String, Float>();
			for (r in ranked) {
				if (topKey.length >= 10) break;
				if (r.isFit == Fitness.NEG_INF) break;
				var key = Canonical.structuralKey(r.g);
				if (seen.exists(key)) continue;
				seen.set(key, true);
				topKey.push(key);
				topFit.set(key, r.isFit);
			}
			if (topKey.length == 0) {
				Sys.println('  no valid champions to re-check.');
			} else {
				var genomesByKey = [for (key in topKey) {key: key, g: popG[keyToIdx.get(key)[0]]}];
				var freshSeed = simSeed + gens + 1000; // outside the 0..gens-1 range every generation used
				var freshZ = competeGenerationFitness(genomesByKey, competeAgents, simSteps, freshSeed);
				var shown = 0, held = 0;
				for (key in topKey) {
					shown++;
					var z = freshZ.get(key);
					var holdMark = z > 0 ? "HELD" : "did not hold";
					if (z > 0) held++;
					var g = popG[keyToIdx.get(key)[0]];
					Sys.println('  ${pad(Std.string(shown), 2)}. trainZ=${fmt(topFit.get(key), 4)}  freshZ=${fmt(z, 4)}  [$holdMark]  ${g.name}');
				}
				Sys.println('fresh-market summary: ${held}/${shown} of the top training performers still scored above the cohort mean in a brand-new market.');
			}
		}
		#end
		if (scheduleSegments != null) {
			if (lastFitnessReal != null) printRealHoldout(lastFitnessReal);
			#if kestrel
			if (lastFitnessCompete != null) printCompeteHoldout(lastFitnessCompete);
			#end
		} else if (competeFlag) {
			#if kestrel
			printCompeteHoldout(lastFitnessCompete);
			#end
		} else {
			printRealHoldout(lastFitnessReal);
		}

		cache.close();
		triageCache.close();
		host.close();
		Sys.println("\nCORPUS_EVO_OK");
	}

	/**
	 * `basket` is `[bars]` for an ordinary single-`--tape` run (see CorpusEvoRun's own doc comment
	 * on `isBasket`) -- the loop below runs exactly once per job in that case, and
	 * `BasketFitness.aggregateBasket` on a one-element array returns that one result unchanged for
	 * any VALID eval, so single-symbol behavior is unaffected.
	 */
	static function evalWorker(engine:Engine, basket:Array<Array<Bar>>, jobs:Deque<EvalJob>, results:Deque<EvalResult>, acks:Deque<Int>, costBps:Float, ?curriculumWeights:Array<Float>):Void {
		var host = new GraalWasmHost(engine);
		host.costBps = costBps;
		var instances = new Map<String, StrategyInstance>();
		while (true) {
			var job = jobs.pop(true);
			if (job.stop) { host.close(); acks.add(1); return; }
			var inst = instances.get(job.wasmPath);
			if (inst == null) {
				inst = host.instantiate(host.loadModuleFile(job.wasmPath), job.strings);
				instances.set(job.wasmPath, inst);
			}
			var perSymbol:Array<{trades:Int, sharpe:Float, finalEquity:Float}> = [];
			var firstFills = null;
			for (i in 0...basket.length) {
				var r = inst.run(basket[i], new Map());
				if (i == 0) firstFills = r.fills;
				perSymbol.push({trades: r.trades, sharpe: r.sharpe, finalEquity: r.finalEquity});
			}
			var agg = BasketFitness.aggregateBasket(perSymbol, curriculumWeights);
			// Behavioral-descriptor inputs (see MapElites.hx) computed HERE, on the worker thread,
			// from basket[0]'s fills -- the same "stay scoped to one representative symbol" choice
			// triage/the attribution oracle already make; MAP-Elites niching is a diversity signal,
			// not the fitness itself, so it doesn't need the full basket.
			var desc = MapElites.describeFills(firstFills, basket[0].length);
			results.add({key: job.key, trades: agg.trades, sharpe: agg.sharpe, finalEquity: agg.finalEquity,
				avgHold: desc.avgHold, longFrac: desc.longFrac, perSymbolSharpe: [for (p in perSymbol) p.sharpe]});
		}
	}

	/**
	 * MAP-Elites immigrant injection: after EvolutionEngine.step()'s raw-fitness-driven selection
	 * has already run, splice in archive champions from behavioral cells the fresh population
	 * DOESN'T currently contain. This is what actually prevents the collapse-to-one-basin failure
	 * mode observed in the corpus runs -- the archive alone (offer-only, no injection) would just
	 * be a passive report; a basin that raw-fitness selection has already crowded out would never
	 * get back INTO the population without this step, since tournament selection only ever draws
	 * from what's already there.
	 *
	 * Never touches the top `eliteCount` slots (EvolutionEngine.step already put its own raw-
	 * fitness elites there — immigrants compete for FUTURE generations via selection, they don't
	 * bypass it by force-replacing a proven performer). Replaces a random subset of the remaining
	 * (crossover/mutation-produced) slots, sized by `rate`, and only with archive genomes whose
	 * structural key isn't already present in this generation (no point re-injecting a niche
	 * champion the population already carries).
	 */
	static function injectArchiveDiversity(pop:Array<StrategyGenome>, archive:EliteArchive, eliteCount:Int, rate:Float, rng:musescript.evo.Rand):Array<StrategyGenome> {
		if (pop.length <= eliteCount) return pop;
		var present = new Map<String, Bool>();
		for (g in pop) present.set(Canonical.structuralKey(g), true);
		var candidates = [for (g in archive.elites()) if (!present.exists(Canonical.structuralKey(g))) g];
		if (candidates.length == 0) return pop;
		// Fisher-Yates shuffle candidates so repeated calls don't always inject the same niches
		// first when there are more candidates than slots.
		for (i in 0...candidates.length - 1) {
			var j = i + rng.int(candidates.length - i);
			var t = candidates[i]; candidates[i] = candidates[j]; candidates[j] = t;
		}
		var replaceableSlots = [for (i in eliteCount...pop.length) i];
		for (i in 0...replaceableSlots.length - 1) {
			var j = i + rng.int(replaceableSlots.length - i);
			var t = replaceableSlots[i]; replaceableSlots[i] = replaceableSlots[j]; replaceableSlots[j] = t;
		}
		var maxInject = Std.int(Math.max(0, Math.round(replaceableSlots.length * rate)));
		var n = Std.int(Math.min(maxInject, candidates.length));
		for (i in 0...n) pop[replaceableSlots[i]] = candidates[i];
		return pop;
	}

	/**
	 * Periodic real-world reality check (`--distill-every`): pools every archive's `elites()`
	 * (same hall-of-fame source `mergerEvent` draws from), re-scores EACH one against the real
	 * `isBasket` multi-symbol data via `Fitness.evaluate` + `BasketFitness.aggregateBasket` --
	 * NOT whatever synthetic real-tape sharpe or compete z-score originally got it archived --
	 * ranks by real aggregate sharpe, and splices the top `k` real-world performers directly into
	 * the population's non-elite slots. Mirrors `injectArchiveDiversity`'s own slot-selection
	 * pattern exactly (never touches the top `eliteCount` slots; a random subset of the rest) --
	 * just a different, real-data-ranked source instead of archive-fitness-ranked, and no
	 * cloning/mutation (these are already-proven genomes, spliced in as-is). Runs regardless of
	 * which mode is currently active -- a plain population-level operation, same as the merger
	 * event.
	 */
	static function distillReinject(pop:Array<StrategyGenome>, archives:Array<EliteArchive>, k:Int, eliteCount:Int,
			isBasket:Array<Array<Bar>>, costBps:Float, startCapital:Float, equityFloor:Float, rng:musescript.evo.Rand):Array<StrategyGenome> {
		if (pop.length <= eliteCount) return pop;
		var pooled:Array<StrategyGenome> = [];
		for (a in archives) for (g in a.elites()) pooled.push(g);
		if (pooled.length == 0) return pop;
		var scored = [for (g in pooled) {
			var anyErr = false;
			var perSymbol:Array<{trades:Int, sharpe:Float, finalEquity:Float}> = [];
			for (sym in isBasket) {
				var fr = Fitness.evaluate(g, sym, "js", false, costBps, startCapital, equityFloor);
				if (!fr.ok || fr.bankrupt) { anyErr = true; break; }
				perSymbol.push({trades: fr.trades, sharpe: fr.sharpe, finalEquity: fr.finalEquity});
			}
			var realSharpe = Fitness.NEG_INF;
			if (!anyErr) {
				var agg = BasketFitness.aggregateBasket(perSymbol);
				if (agg.trades >= 1 && !Math.isNaN(agg.sharpe)) realSharpe = agg.sharpe;
			}
			{g: g, realSharpe: realSharpe};
		}];
		scored.sort((a, b) -> a.realSharpe < b.realSharpe ? 1 : (a.realSharpe > b.realSharpe ? -1 : 0));
		var present = new Map<String, Bool>();
		for (g in pop) present.set(Canonical.structuralKey(g), true);
		var candidates = [for (s in scored) if (s.realSharpe != Fitness.NEG_INF && !present.exists(Canonical.structuralKey(s.g))) s.g];
		if (candidates.length == 0) return pop;
		if (candidates.length > k) candidates = candidates.slice(0, k);
		var replaceableSlots = [for (i in eliteCount...pop.length) i];
		for (i in 0...replaceableSlots.length - 1) {
			var j = i + rng.int(replaceableSlots.length - i);
			var t = replaceableSlots[i]; replaceableSlots[i] = replaceableSlots[j]; replaceableSlots[j] = t;
		}
		var n = Std.int(Math.min(candidates.length, replaceableSlots.length));
		for (i in 0...n) pop[replaceableSlots[i]] = candidates[i];
		Sys.println('  distill: re-scored ${scored.length} archive genome(s) against real data, injected $n top real-world performer(s)');
		return pop;
	}

	/**
	 * Rare "merger" crossover event: draws the top `k` genomes from the MAP-Elites archive(s)
	 * (the hall-of-fame across generations AND modes -- an archive cell only changes occupant
	 * when strictly beaten, so old champions persist there for free), splits the draw roughly
	 * evenly across whichever archives are populated (this IS the "different generations and
	 * trading styles" the user asked for -- `archiveReal`/`archiveCompete` are shaped by
	 * fundamentally different pressures), tries every pairwise `Variation.crossover`
	 * recombination among the draw, and returns the single best-scoring hybrid.
	 *
	 * `evalBatch` scores ALL candidate hybrids in one call rather than one at a time: under
	 * `--compete`, a lone genome's z-score against itself is meaningless (mean=itself, std=0),
	 * so the caller batches every hybrid into ONE shared compete cohort instead (see the call
	 * site) -- under real-tape fitness, each hybrid's sharpe is independent anyway, so the
	 * caller just maps `evalFn` over the batch there.
	 *
	 * Returns null (a plain no-op, never a crash) when fewer than 2 total candidates are
	 * available across all archives -- expected during early generations before any archive has
	 * accumulated enough entries.
	 */
	static function mergerEvent(archives:Array<EliteArchive>, k:Int, evalBatch:Array<StrategyGenome>->Array<Float>, variation:Variation):Null<{hybrid:StrategyGenome, fitness:Float, sourceKeys:Array<String>, parentFitness:Array<Float>}> {
		var populated = [for (a in archives) if (a.size() > 0) a];
		if (populated.length == 0) return null;
		var perArchive = Std.int(Math.ceil(k / populated.length));
		var sources:Array<{g:StrategyGenome, key:String, f:Float}> = [];
		for (a in populated) {
			var entries = a.entries();
			entries.sort((x, y) -> x.cell.fitness < y.cell.fitness ? 1 : (x.cell.fitness > y.cell.fitness ? -1 : 0));
			for (i in 0...Std.int(Math.min(perArchive, entries.length)))
				sources.push({g: entries[i].cell.genome, key: entries[i].key, f: entries[i].cell.fitness});
		}
		if (sources.length > k) sources = sources.slice(0, k);
		if (sources.length < 2) return null;
		var pairs:Array<{i:Int, j:Int}> = [];
		var hybrids:Array<StrategyGenome> = [];
		for (i in 0...sources.length - 1) {
			for (j in (i + 1)...sources.length) {
				pairs.push({i: i, j: j});
				hybrids.push(variation.crossover(sources[i].g, sources[j].g));
			}
		}
		var fits = evalBatch(hybrids);
		var bestIdx = 0;
		for (i in 1...fits.length) if (fits[i] > fits[bestIdx]) bestIdx = i;
		var p = pairs[bestIdx];
		return {hybrid: hybrids[bestIdx], fitness: fits[bestIdx], sourceKeys: [sources[p.i].key, sources[p.j].key],
			parentFitness: [sources[p.i].f, sources[p.j].f]};
	}

	/**
	 * Multiplies a merger event's winning "super-genome" into `count` copies (the hybrid itself
	 * unmutated, plus `count - 1` mutated clones via `variation.mutate`), spliced into the
	 * population's non-elite slots -- mirrors `injectArchiveDiversity`'s own slot-selection
	 * pattern above (never touches the top `eliteCount` slots; a random subset of the rest).
	 */
	static function injectMergerClones(pop:Array<StrategyGenome>, hybrid:StrategyGenome, count:Int, eliteCount:Int, variation:Variation, rng:musescript.evo.Rand):Array<StrategyGenome> {
		if (pop.length <= eliteCount || count <= 0) return pop;
		var replaceableSlots = [for (i in eliteCount...pop.length) i];
		for (i in 0...replaceableSlots.length - 1) {
			var j = i + rng.int(replaceableSlots.length - i);
			var t = replaceableSlots[i]; replaceableSlots[i] = replaceableSlots[j]; replaceableSlots[j] = t;
		}
		var n = Std.int(Math.min(count, replaceableSlots.length));
		for (i in 0...n) pop[replaceableSlots[i]] = i == 0 ? hybrid : variation.mutate(hybrid);
		return pop;
	}

	static function emitGenome(g:StrategyGenome):Null<{wat:String, strings:Array<String>}> {
		try {
			var source = Expand.expand(g);
			var prog = new MuseParser().parse(source, "<evo>");
			prog = TemplateExpand.expand(prog);
			prog = ModuleExpand.expand(prog);
			prog = SeriesLowering.lower(prog);
			return new StrategyWasmEmitter().emitOnBar(prog);
		} catch (e:Dynamic) {
			return null;
		}
	}

	static function loadBars(explicitPath:Null<String>):Array<Bar> {
		var candidates = explicitPath != null
			? [explicitPath]
			: ["data/real/spy.csv", "muse-script/data/real/spy.csv", "../muse-script/data/real/spy.csv"];
		for (path in candidates)
			if (sys.FileSystem.exists(path)) return OhlcvCsv.parse(sys.io.File.getContent(path));
		throw '${explicitPath != null ? explicitPath : "spy.csv"} not found -- run from muse-lab/muse-script';
	}

	static function argStr(name:String, dflt:Null<String>):Null<String> {
		var args = Sys.args();
		for (i in 0...args.length - 1) if (args[i] == name) return args[i + 1];
		return dflt;
	}

	static function argFloat(name:String, dflt:Float):Float {
		var args = Sys.args();
		for (i in 0...args.length - 1) {
			if (args[i] == name) {
				var v = Std.parseFloat(args[i + 1]);
				if (!Math.isNaN(v)) return v;
			}
		}
		return dflt;
	}

	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}

	static function argInt(name:String, dflt:Int):Int {
		var args = Sys.args();
		for (i in 0...args.length - 1) {
			if (args[i] == name) {
				var v = Std.parseInt(args[i + 1]);
				if (v != null) return v;
			}
		}
		return dflt;
	}

	static function fmt(x:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		var r = Math.ffloor(x * m + 0.5) / m;
		return Std.string(r);
	}

	static function pad(s:String, n:Int):String {
		while (s.length < n) s = " " + s;
		return s;
	}

	static function count(m:Map<String, ModuleEntry>):Int {
		var n = 0;
		for (_ in m.keys()) n++;
		return n;
	}
}
