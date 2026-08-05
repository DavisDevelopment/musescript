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
         OR panel runPanelBacktest when panelFeed + PanelAction
  → EvolutionEngine                → selection / elitism
```

**Panel fitness:** attach a `PanelFeed` via `Fitness.configurePanel` or
`EvolutionEngine.configureForPanel(panel)` (also gates Variation universe growth).
Genomes with `panelAction` score through the portfolio path (`buy` /
`rebalance_equal` / `target_weight` / closed `bag_from_scan`·`bag_norm` →
`portfolio_apply`). Classic genomes (`panelAction == null` and no `KPd` xs_rank)
stay on single-name `OrderSim` even if a panel is attached. Compose with
`configureForTape` for aux field pools.

**Closed NP / PD palette (gated, default off):** host `muse.np` / `muse.pd` are
not open-world Expand trees. Opt in with:

```text
engine.configureForPanel(panel)   # PanelFeed → Fitness.configurePanel + universe
engine.configureForUniverse([...]) # if panel not used; required for xs_rank
engine.configureForPd(null)       # KPd → pd_rank1d (≤64) / frame pd_xs_rank
                                  # → target_weight and/or closed rank→bag templates;
                                  # and/or size-safe pd_shift
engine.configureForNp(null)       # or ["mean","dot","sum"] — KNp → np_mean/np_dot/np_sum
```

PD `xs_rank` genomes Expand to runnable panel MS (`target_weight` / HostABI, or
closed `portfolio_apply(bag_from_scan({…}, k))` /
`portfolio_apply(bag_norm(bag_from_dict({…ranks…})))`). No open `bag_rank_*` /
`symbols()` / `dict_new` loops in Expand. Size-safe `shift` stays on classic
single-name fitness. Closed bags HostABI on WASM (`apply_bag_*` incl. bottom scan / raw dict /
`bag_equal` / `bag_pair`); open bags / bag locals stay U.
Fitness uses `runPanelBacktest` when `configureForPanel` is set for panel/xs_rank
genomes. NMA columnarizes closed
**NP** (`np_mean`/`np_sum`/`np_dot` of trailing `window` over SPrice/SInd) and cliff-3
closed **SPanel** (`PanelInline` → `field@SYM`) with `PABuy`/`PARebalance`/`PATargetWeight`
and closed bag templates **`PABagScanTop`** / **`PABagRankWeights`** (columnar scores →
equal bag or percentile xs_rank → `bag_norm` → `applyBag`) on packed `PanelFeed` columns
(`preferNma` → backend `nma`). Closed **PD** `KPd("shift")` is also columnar-NMA
(lookback of OHLC field); `KPd("xs_rank")` stays `nma-unsupported` (panel/frame Expand).
Open `bag_rank_*` / `symbols()` stay out of Expand and NMA. Bytecode VM also runs closed NP
(`VmNpEligibility`), packed `pd_rank1d`, Series-lane `pd_series`/`pd_shift`/
`pd_series_values`, and gated Frame-lane `pd_from_columns`/`pd_xs_rank`/groupby/`pd_join`
(`VmPdEligibility`); Expand `KPd("xs_rank")` / panel stay `vm-unsupported` while gated
`KPd("shift")` may hit `--vm`. WASM may claim native for
the NP scalar subset and for size-capped Expand `pd_rank1d` (`WasmPdEligibility`);
wide frame `pd_xs_rank` remains WASM-U (honest fallback).

**Offline loaders / CLI:** `PanelLoader` (`json` bySym, long CSV + `symbol`,
`--tapes SYM=path`, dir of CSVs). GeneRunner:

```text
node build/js/gene-runner.js --source scan.ms --panel data/fund_panel.json
CorpusEvoRun --panel data/fund_panel.json   # configureForPanel + panel session tape
```

Pre-join DB panels with `tools/fund_panel_loader.py` (offline sqlite/duckdb → JSON).

**NMA / VM:** closed `SPanel` + `PABuy`/`PARebalance`/`PATargetWeight`/`PABagScanTop`/
`PABagRankWeights` are nma-fast via `PanelInline` + panel packing (`preferNma`). Closed
`KNp` and `KPd("shift")` are columnar-NMA. Open panel genomes and `KPd("xs_rank")`
remain Expand→interp/WASM (`nma-unsupported` / `vm-unsupported`); Series `KPd("shift")`
may also hit bytecode VM when NMA is off. Open `bag_rank_*` / `symbols()` stay out of
Expand and NMA.

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

## Node NMA throughput bench

`CorpusEvoRun` is JVM-only. For V8 A/Bs on the same smoke tape:

```powershell
haxe build-nma-node-bench.hxml
node build/js/nma-node-bench.js --pop 1000 --gens 6 --tape build/graal/smoke_spy_320.csv --nma-dirty-spine
node build/js/nma-node-bench.js --pop 1000 --gens 6 --threads 4 --tape build/graal/smoke_spy_320.csv
```

Reports mean `wallMs`/`scoreMs`. `--threads N` fans the population fitness barrier across Node `worker_threads` (`NmaNodeEvalPool`); `EvolutionEngine.step` stays serial. Dirty-spine is refused when `threads > 1`.

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
| `--panel PATH` | Offline `PanelLoader` → `configureForPanel` (PanelAction portfolio fitness; optional session tape when no `--tape`) |
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
| `--rivalry` | Umbrella: demes ~128, arena every 50 gens, mid-arena retunes (2), `--rivalry-weight 0.40` into selection, **Foundry every 25 gens** (OOS gate). Sparse — **not** every-gen Murmuration |
| `--arena-every N` / `--arena-steps N` / `--arena-retune-rounds N` | Sparse arena cadence / tick budget / mid-arena response rounds |
| `--rivalry-weight W` | Selection blend weight (default 0.40 under `--rivalry`). Scale-safe z-norm blend so arena z can unseat tape-only elites |
| `--foundry-every N` / `--foundry-bags` / `--foundry-perms N` | Rare fork→consensus Foundry with **real OOS / multi-bag gate** (Fitness+BasketFitness over held-out `oosBasket`). Off by default; under `--rivalry` defaults to every **25** gens. Set `--foundry-every 0` to disable. Bags: `auto` + `--tapes` labels |
| `--proj-map-axis` | MAP-Elites niches by purged OOS forecast skill (5th CVT axis). **Not** additive `--proj-weight`. |
| `--proj-ablate` | Deposit projection-ablation Δ → `NmaCreditBank` `proj:` + `GrowthWeights.projRead` |
| `--ccea` | P5 two-pop forecaster×manager mini-loop on IS tape, then exit (`CceaCoEvo.runMini`) |
| `--ccea-gens` / `--ccea-f-pop` / `--ccea-m-pop` | CCEA gens / forecaster pop / manager pop (defaults 3 / 4 / 4) |

Oracle scoring: always use `Fitness.score` / `Fitness.scoreFacts` (bankrupt → NEG_INF).

### Projection co-evo (skill axis + CCEA)

```powershell
# MAP niches by purged skill (preferred selection story)
haxe build-corpus-evo.hxml
# java … CorpusEvoRun --proj-map-axis [--ew-host] [--proj-ablate] --tape …

# CCEA two-pop smoke (coupled trading fitness; skill is telemetry / niche, not --proj-weight)
# java … CorpusEvoRun --ccea --ccea-gens 3 --proj-ablate --tape build/graal/smoke_spy_320.csv

# Node projection scaffold + CCEA unit tests
haxe build-projection-host-tests.hxml
node build/js/tests-projection-host.js
```

Rivalry smoke (GraalVM + `graal/cp.txt`):

```powershell
haxe build-corpus-evo.hxml
$env:JAVA_HOME = "C:\Users\epiki\graalvm\graalvm-community-25.1.3"  # or your Graal home
$JAVA = Join-Path $env:JAVA_HOME "bin\java.exe"
$CP = (Get-Content graal\cp.txt -Raw).Trim()
& $JAVA --sun-misc-unsafe-memory-access=allow -cp "$CP;build\jvm\corpus-evo.jar" `
  musescript.evo.graal.CorpusEvoRun `
  --pop 128 --nma --rivalry --arena-every 2 --arena-steps 200 --foundry-every 2 --foundry-perms 4 --gens 4 `
  --tape build/graal/smoke_spy_320.csv --threads 1 --fitness-windows 1 --attr-bars 128 --no-cache
# expect: RIVALRY umbrella on (weight=0.4, retuneRounds=2, foundry every 2);
# arena START / heartbeats / DONE with retunes>0; foundry START / [fork|trials|consensus|reject] / KEEP|REJECT
# demes ~128 need --pop >= 256 (else panmictic cohort of --arena-k)
```

Arenas stay off the NMA daily path unless `--rivalry` / `--arena-every` is set. Foundry OOS eval is sparse (`--foundry-every`) and never on the per-gen NMA hot path.

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

## FeatureViz (shared TA / forecast overlay contract)

`FeatureVizEvent` (`FeatureVizEvent.hx`) is the scrub-/gen-boundary POD for painting
advanced TA and MC forecasts in `--gui` / the app — and later as website replay frames.
Not the indicator hot-path `GeomViz` LevelSet slots; those stay inside libs.

| field | role |
|---|---|
| `kind` | `fib` (live) · `elliot` / `forecast` (reserved) · extensible string |
| `barLo` / `barHi` | inclusive bar range this frame describes |
| `payload` | `levels`, `anchors`, optional `confidence` / `paths` / `note` / `extra` |
| `genomeKey` / `sourceId` / `epoch` | optional provenance (champion name, `fib_retracement:20`, gen) |

**Emit:** `FeatureVizFib.snapshotTape` walks the IS tape once through the existing
`FibRetracement` engine (same math as `NmaFeatureHost` / IndicatorCache) — no second fib.
`CorpusEvoRun` pushes the frame into `EvoDashboardWindow.updateFeatureViz` at each
generation boundary when `--gui` is on.

**Consume:** Swing paints a compact level list under the niche panels. Full OHLC overlay
belongs in the app chart workbench; website = recorded-frame replay of the same JSON.

**Cadence rule:** gen-boundary or explicit scrub only — never per Murmuration tick, and
don't couple rivalry arenas onto the EDT without this snapshot bus.

## Layout

| module | role |
|---|---|
| `FeatureVizEvent` | shared fib/elliot/forecast overlay POD + bus + FibRetracement emit |
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
| `CceaCoEvo` | P5 two-pop forecaster×manager; coupled trading fitness |
| `ProjectionAblation` / `ProjectionScore` | module credit + purged OOS skill |
| `EvoProof` | seeded demonstration |
| `jenetics/JeneticsNotes` | classpath contract |
