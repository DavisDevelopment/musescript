# Evo-run speed plan — make CorpusEvoRun *many times* faster without losing effectiveness

**Status: PLANNED — execute phases in order. Written 2026-07-22 (Fable), for Sonnet to carry out.**

> ⚠️ **HARD RULE before touching anything:** do NOT run `haxe build-corpus-evo.hxml` (or any
> build that rewrites `build/jvm/corpus-evo.jar`) while a backgrounded corpus-evo run is alive.
> The JVM lazy-loads classes from the jar mid-run; rebuilding it corrupted two runs tonight
> (one hang at gen 19, one `NoClassDefFoundError: haxe/generated/Anon154` at the finish line).
> Check first: `wmic process where "name='java.exe'" get ProcessId,CommandLine | grep CorpusEvoRun`
> and wait for the task-completion notification for run `b7xn2clqp` (log:
> `build/graal/fibfourier_run4.log`) before the first rebuild.

## Where the time actually goes (measured, not guessed)

Baseline: pop=80, gens=30, NVDA 5161 IS bars, cost=20bps → **mean 22.9s/gen warm** (run2,
21 gens measured), spikes to 40s. The per-gen *fitness* pass is NOT the cost: ~80 evals, mostly
structural-key cache hits + parallel GraalWasm workers.

The whale is the **attribution oracle** (`evalFn` in CorpusEvoRun.hx:390, currently
`Fitness.evaluate(g, bars, "js", false, costBps)` = full 5161-bar MuseInterp backtest including
parse + the full 8-pass compile pipeline, **serial, on the main thread, with zero caching**).
Call sites per generation (EvolutionEngine.step, Variation.hx):

| caller | when | oracle calls each |
|---|---|---|
| `attributedSubtreeCrossover` | **every** non-elite child (~75/gen) | 1 baseline + ~4–10 site ablations + ≤6 donor evals |
| `attributedPointMutate` | mutateProb (0.3–0.85) of children | 1 baseline + ~4–10 ablations + 1 child re-eval |

≈ **1,000–1,500 serial full-tape interp evals per generation** vs ~80 for actual fitness.
The oracle is ~95% of wall time. Everything below attacks that, then the residuals.

Targets: **< 5s/gen warm** after P0–P2; stretch < 2s/gen after P3/P4.

---

## P0 — Memoize the oracle (zero behavior change, biggest single win)

Two independent caches, both exact (same inputs ⇒ same outputs, no fidelity tradeoffs):

**(a) Route the oracle through the existing `EvoCache`.** The oracle evaluates on the SAME
`bars` + `costBps` as the fitness pass, so it can share the *same* memo file
(`5161_..._cost200.tsv`). In `CorpusEvoRun.main`, replace the bare lambda with one that:
1. computes `key = Canonical.structuralKey(g)`,
2. on hit → `Fitness.score`-equivalent from the `CachedEval` (raw sharpe, `trades>=1`,
   NaN check — replicate score's NEG_INF contract; note the oracle deliberately does NOT
   apply parsimony, which the CachedEval-based scoring naturally matches),
3. on miss → run `Fitness.evaluate`, `cache.put` the raw result (fills descriptor fields via
   `MapElites.describeFills` like the fallback path does), return the score.

Why this wins so hard: elitism + tournament selection re-pick the same parents constantly
(baseline evals), ablation shapes recur across children (`x && (1>0)` collapses…), and the
child's own fitness pass next generation hits the same key. After gen ~2 most oracle calls
should be O(1) lookups. **The champion-determinism check at the end of the run stays a real
double-execution — don't route IT through the cache.**

**(b) Compiled-program cache inside `Fitness`.** `evaluate()` currently re-parses and re-runs
TemplateExpand→…→CallsiteIds for every call. Add a `static var fnCache:Map<String,
{fn:BarStrategyFn, prog:MuseProgram, backend:String}>` keyed on `structuralKey + ":" + target`.
On hit, skip parse+passes; per eval still do the cheap fresh-state setup **in this order**:
fresh `HarnessContext`, set `slippageBps` from `costBps`, `new MuseInterp(harness)` +
`registerDeclPublic` for each cached `prog.decls`, set `harness.feed`,
`TradeBuiltins.resetCrossState()`, then call the cached `fn(harness)`. Bound the map (e.g.
LRU-ish clear at 4096 entries — a plain "clear all when full" is fine, it's a cache).
Add `Fitness.clearFnCache()` and call it in test setup if any test asserts compile counts.

*Verify:* full JS suite green; a same-seed 8-gen A/B (old jar vs new) produces **identical**
per-gen `best/mean/niches` lines (this phase must be bit-identical) with wall time down.
Expected: 22.9s/gen → roughly 3–6s/gen.

## P1 — Stop paying for redundant oracle work (near-exact, tiny behavior deltas, flag-gated)

1. **Per-parent ablation memo, per generation.** In `Variation`, memoize
   `siteDeltas` by `Canonical.structuralKey(g1)` in a map the engine clears each `step()`
   (add `variation.beginGeneration()` or pass a gen counter). Tournament re-picks elites many
   times per gen; their ablation profile is deterministic — recomputing it per child is pure
   waste. Exact same results (P0a already makes the *evals* cheap; this removes even the
   lookups/tree-surgery).
2. **`--attr-cross-prob` (default 0.5):** attributed crossover currently runs for EVERY child.
   Gate it: with prob p use attributed, else blind `subtreeCrossover`. Rationale: attribution's
   value concentrates in protecting elite parents' load-bearing nodes; a 50% blend keeps that
   while halving oracle traffic and *adding* exploration (the same explore-pressure argument as
   the existing 20% fallback inside the operators).
3. **`--donor-cap` (default 4, was 6).**

*Verify:* same-seed A/B vs P0 baseline — wall time down further; champion fitness and OOS
hold-rate within noise (run 2–3 seeds if the single-seed delta looks large). Full suite green
(the statistical operator tests in TestEvoVariation call the operators directly and are
unaffected by the CLI gates).

## P2 — Shrink the oracle's tape (honest fidelity tradeoff, flag-gated, A/B-verified)

Attribution needs a *ranking* signal ("which node matters more", "which donor helps more"),
not a full-precision Sharpe. Add `--attr-bars` (default: the triage prefix length, i.e.
`bars.length/5` ≈ 1032; `0` = full tape = old behavior). The oracle evaluates on
`bars.slice(0, attrBars)`; cache these in the **triage** EvoCache (prefix-tape signature file
— it already exists and already has the right keying), NOT the full-tape cache.
`attributedPointMutate`'s final `childFitness - baseline` reward for GrowthWeights also uses
the prefix — deltas stay internally consistent since baseline and child use the same tape.

This is the one phase that changes selection behavior measurably (5× fewer bars per miss).
*Verify honestly:* same-seed, full 30-gen A/B on NVDA — compare champion IS fitness, OOS
hold-rate, niches. Accept if OOS/champion quality is within noise; revert default to full tape
(keep the flag) if it visibly degrades. The existing TestEvoVariation statistical tests already
run on 300–500-bar tapes, so short-tape attribution soundness is precedented.

## P3 — Parallelize the serial interp evals (gated on a parity probe)

`fallback=25–42` genomes/gen each run a full-tape interp eval serially on the main thread; the
oracle misses do too. Interp state *should* be harness-local since the CallsiteIds pass
(`crossoverCS` state on `harness.indCols.csPairs`, indicator columns on the harness — the
statics in TradeBuiltins only back NON-wrapped calls, and genome-expanded code is always
wrapped), but this has never been proven under concurrency.

1. **Probe first (throwaway, delete after):** evaluate the same 3 genomes on 4 threads
   concurrently × 50 reps; assert every result identical to serial. If ANY divergence → stop,
   ship P0–P2 only, and note the finding. (`TradeBuiltins.resetCrossState()` touches statics —
   if the probe fails, the likely fix is skipping that call for wrapped-only programs, but do
   not go down that hole without the probe failing first.)
2. If green: worker-pool the `fallbackMiss` loop (plain Haxe `sys.thread` pool, per-thread
   nothing shared but the result queue — same shape as the existing GraalWasm worker pool) and
   make the oracle's `Fitness.evaluate` misses safe to call from `attributed*` (they already
   run on the main thread only — parallelizing *those* means batching ablation candidates,
   which is a bigger refactor; only do the fallback loop unless P0–P2 left the oracle as a
   visible residual).

*Verify:* determinism A/B (parallel vs serial same-seed → identical gen lines), suite green.

## P4 — GraalVM-level residuals (measure, don't assume)

1. **A/B removing `engine.LastTierCompilationThreshold=2000000000`.** That option currently
   *disables* last-tier Truffle compilation of WASM modules. Worker instances persist and
   replay 5161 bars × 30 gens for recurring modules — last-tier JIT may pay for itself.
   Measure a same-seed run with the option removed; keep whichever wall time wins.
2. **Kill the Python `wat2wasm` subprocess** (`tools/wat2wasm_batch.py`, spawned once per gen
   with `new>0`): the repo has an in-tree WAT assembler (see TestWatAssembler.hx, built for
   the JS target's self-contained path). If it compiles on the JVM target, assemble in-process.
   Saves process-spawn + Python startup per gen (~0.2–0.5s/gen) and removes the `.venv`
   dependency. Lower priority; skip if the assembler is JS-target-coupled.
3. **Add `--enable-native-access=ALL-UNNAMED`** to the java invocation (silences the Truffle
   restricted-method warnings; zero perf but removes log noise).
4. **`--threads` default:** currently `cores/2`; try `cores-1` for the WASM pool in an A/B.
   (Only matters once fallback/oracle serial work stops dominating.)

## Effectiveness guardrails (apply to every phase)

- Full JS suite (`haxe build.hxml && node build/js/tests.js`) green after each phase.
- Same-seed A/B against the pre-phase jar for: champion fitness, OOS hold-rate (top-10),
  niches occupied, wall time. P0/P1.1/P3 must be *identical* results; P1.2/P1.3/P2/P4.1 must be
  *within noise* (multi-seed if unclear). Report regressions honestly — do not ship a default
  that trades measurable OOS quality for speed; leave it behind a flag instead.
- Never route the end-of-run champion determinism check through any cache.
- New CLI flags documented in CorpusEvoRun's usage doc comment.
- The GUI dashboard update call (`--gui`) is per-generation and negligible; don't touch it.

## Expected outcome

P0 alone should take ~23s/gen → ~3–6s/gen (oracle becomes cache-dominated). P1+P2 push the
remaining miss cost down ~5–10×. P3/P4 clean up the residual serial evals and per-gen fixed
costs. Combined honest target: **sub-2s/gen warm at pop=80** — i.e. a 30-gen run in about a
minute instead of ~12, with equal-or-better search effectiveness (P1.2's added exploration and
P2's cheaper oracle also mean MORE attributed guidance per wall-second, which is the "ideally
gaining some" part).
