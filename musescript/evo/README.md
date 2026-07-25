# MuseScript Evolution Adapter (Haxe)

Strongly typed MuseGene IR + evolutionary operators authored in Haxe
(`musescript/evo/`), with Jenetics 8.3.0 available on the JVM classpath for
production population lifecycle.

```
StrategyGenome (Haxe enums)
  → Variation.mutate / crossover   (typed, no repair)
    → Expand.expand()                → MuseScript source
    → Fitness.evaluate()             → MuseCompiler (js/wasm/interp)
         OR NmaFitness (columnar) when Fitness.preferNma / --nma
  → EvolutionEngine                → selection / elitism
```

Jenetics (`io.jenetics:jenetics:8.3.0`, Java 21) is the preferred host for
Engine/selection when deploying on JVM; the Haxe `EvolutionEngine` is the
reference / proof implementation so the pipeline is testable without hand-written Java.

Spec board: `muse-lab/muse-nse/muse_nse_spec.md` §8.

## Build / run proof

```powershell
haxe build-evo.hxml
node build/js/evo-proof.js

haxe build-evo-jvm.hxml
java -jar build/jvm/evo-proof.jar
```

Proof checks: seeded population, typed mutation, elitism non-regression,
deterministic re-evaluation of the champion.

## Corpus evo flags (innovation + NMA)

Primary entry: `CorpusEvoRun` (`build-corpus-evo.hxml`). Useful strangler / search flags:

| Flag | Role |
|---|---|
| `--nma` | Columnar NMA fitness + attr tape; forces JS-fallback pop scoring |
| `--nma-verify` | Double-path: NMA vs Expand→compile, throw on mismatch |
| `--no-nma-pop-memo` | Disable generation-scoped content-addressed column memo |
| `--nma-dirty-spine` | Opt-in guarded live working copies; single-thread only |
| `--nma-fuse-host` / `--nma-fuse-min-bars N` | Opt-in warm BAnd/BOr WASM fuse; single-thread only, conservative default gate 8192 bars |
| `--speculative-growth-k N` | Score N grown replacements with blocked robustness + parent acceptance gate (needs `--nma`) |
| `--speculative-growth-windows N` / `--speculative-growth-lambda X` | Spec-growth v2 blocked score controls (defaults 4 / 0.5) |
| `--speculative-growth-min-delta X` / `--speculative-growth-parsimony X` | Parent acceptance margin / candidate complexity penalty |
| `--exec-profile single\|evo\|prod\|mobile` | PreferNma / caches / prefixAttr / backend knobs |
| `--lexicase` | ε-lexicase selection (single-tape: `Fitness.windowSharpes` cases when `--fitness-windows`>1; multi-`--tapes`: per-symbol) |
| `--cvt-cells N` | CVT MAP-Elites cells — recommended recipe: `--lexicase --cvt-cells 64` |
| `--credit-map-axis` | Research-only 5th CVT axis = credit HHI; **hurt OOS** (26/50 vs CVT 41/50) — keep off full-stack |
| `--semantic-rdo-prob P` | Semantic-RDO mutate (needs NMA) |
| `--attr-bandit` | UCB skip for attr ablations |
| `--credit-cuts` / `--no-credit-cuts` | Zero-oracle ranking when bank warm (ON by default with `--nma`) |
| `--attr-bars N` | Oracle tape length (`0`=full, `N>0`=prefix, `-1`=triage default) |
| `--last-tier` | Allow Graal last-tier WASM compilation (default: threshold disabled) |
| `--wat2wasm-python` | Legacy Python wat2wasm batch (default: in-process WatAssembler) |
| `--learn-library` / `--library-every` | Motif library → `BHole` |
| `--poet` / `--poet-envs` / `--poet-every` | POET envs (kestrel) |
| `--equity-floor` / `--cost-bps` | OrderSim bankruptcy / slippage |

Oracle scoring: always use `Fitness.score` / `Fitness.scoreFacts` (bankrupt → NEG_INF).

## JIT-audited runs (standing practice)

Any evaluation run against a `build/jvm/*.jar` evo entry point (`EvoBench`,
`CorpusEvoRun`, `EvoProof`, ...) should go through `scripts/jit_audit_run.sh`
instead of a bare `java -jar`, so a run that's silently losing throughput to
failed inlining or deopt storms shows up in a log instead of just "feeling
slower":

```bash
scripts/jit_audit_run.sh build/jvm/evo-bench.jar musescript.evo.graal.EvoBench --pop 40 --gens 10
```

Writes `build/graal/jit-audit/<mainClass>_<timestamp>/summary.txt` with top
inlining-rejection reasons and top deopting methods (musescript/haxe.jvm sites
called out separately, since those are the ones actually worth fixing vs.
JDK/Truffle internals). Never point it at `build/jvm/corpus-evo.jar` while a
background corpus-evo run has that same jar open (see `PLAN_EVO_SPEED.md`'s
hard rule) -- check `wmic process where "name='java.exe'" get CommandLine`
first.

## Layout

| module | role |
|---|---|
| `nma/JIT_AUTHORING_GUIDE.md` | Haxe authoring for GraalVM host JIT + V8 (kind-switch, unboxed vecs, Engine reuse, Maps/ICs) |
| `nma/*` | Neural Muse AST substrate (bijection, columnar eval, attr, kernels) |
| `SeriesNode` / `ScalarNode` / `BoolNode` | typed IR |
| `StrategyGenome` / `EvoParam` | genome schema |
| `Palette` | closed primitive set |
| `Expand` | genome → MuseScript |
| `Canonical` | structural key + node count |
| `Variation` | grow / mutate / crossover |
| `Fitness` / `scoreFacts` | compile + backtest + bankrupt-aware oracle |
| `EvolutionEngine` | tournament + elitism (+ lexicase) |
| `EvoProof` | seeded demonstration |
| `jenetics/JeneticsNotes` | classpath contract |
