# Co-evolving ForecastFn + TradeLogic (EW instance #1)

**Date:** 2026-07-27  
**Intent:** Evolved / simulated agents co-evolve a **forecasting/projection function** (often MCMC-like clouds) **and** trading logic that consumes those clouds. EW is the first concrete host; the pattern should generalize (see root `PROJECTION_COEVOLUTION_PLAN.md`).

**Coordination:** EvolutionEngine / Fitness / Variation / StrategyGenome forecasting hooks are **owned by Claude (parallel session)**. This doc defines contracts and handoff points only — no duplicate evo implementation here.

---

## Why promote EW out of `indicators`

Chart indicators emit series for paint and simple signals. EW+MCMC is:

- a **constrained inference engine** (grammar + soft params),
- a **probabilistic forecaster** (clouds, invalidations, UQ),
- a **genome-consumable feature host** for co-evolved traders.

Keeping it under `indicators/` hides that agents will evolve *around* it. `musescript.ew` is the infra leg; `EwHypothesisIndicator` remains a thin streaming/GeomViz facade.

---

## Two modules inside one agent

```text
┌─────────────────────────────────────────────────────────┐
│ Agent genome                                            │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │ ForecastFn           │  │ TradeLogic               │ │
│  │  φ deltas / budget   │→ │  bool/scalar trees       │ │
│  │  host: lattice|mcmc  │  │  read cloud reductions   │ │
│  │  → ForecastCloud     │  │  entry/exit/size         │ │
│  └──────────────────────┘  └──────────────────────────┘ │
│                         ↓                               │
│              Fitness = trade + forecast skill           │
└─────────────────────────────────────────────────────────┘
```

ForecastFn **never** learns hard rules. It may only:

- perturb soft `EwPhiParams`,
- choose sampler budget / seed / host kind,
- (later) propose grammar-*preserving* label moves for MCMC.

TradeLogic never calls `ImpulseRules` directly; it only sees cloud features (`spread`, `prob_up`, `p50`, `dist_to_inv`, …).

---

## Interface contracts (this package)

| Type | Role |
|------|------|
| `ForecastCloud` | Serializable / column-friendly projection UQ surface |
| `EwForecastHost` | Causal producer of clouds + top-K masses |
| `EwForecastHostStub` | Compile/wiring placeholder |
| *(planned)* `LatticeForecastHost` | Wrap today’s lattice + `EwProject` + invalidation |
| *(planned)* `McmcForecastHost` | Hierarchical MH; same interface |

### Fan reductions TradeLogic should see

Aligned with Claude’s projection plan field vocabulary:

| field | from ForecastCloud |
|-------|--------------------|
| `p50` / `mean` | `priceMid` |
| `p05`/`p95` (approx) | `priceLo` / `priceHi` |
| `spread` | `spread` |
| `prob_up` | `probUp` |
| `inv` | `invalidatePrice` |
| `dist_inv` | `distToInvalidation` |
| `entropy` | `countEntropy` |
| `nest` | `nestScore` |

At `samples=1`, quantiles collapse; `spread` may still be φ-band width (informative uncertainty proxy even without MCMC).

---

## Handoff to Claude (boundary X)

```text
musescript.ew.EwForecastHost
        │  cloudAt(t) / topCounts
        ▼
[ Claude ] ProjectionProvider / NmaFeatureHost sibling
        │  SProj("ew_0", field) → columns
        ▼
[ Claude ] StrategyGenome.tradeGenes read SProj
        ▼
[ Claude ] Fitness: equity terms + optional projScore
             (coverage / CRPS / invalidation survivability)
```

**Integrate at boundary X:** host → provider → `SProj` → fitness.  
If Claude’s generic `ProjectionDecl` / `PSPoint`/`PSNoise` lands first, EW is one **named host-backed sampler** (`hostKind: lattice|mcmc`) that fills a `ProjBundle` from `ForecastCloud` rather than from a free SeriesNode tree.

**Do not** (in the ew package session):

- edit `EvolutionEngine.hx`, `Fitness.hx`, `Variation.hx`, or `StrategyGenome.hx` for forecasting,
- invent a second parallel genome projection schema that fights Claude’s.

---

## Genome sketch (docs only)

```haxe
// Illustrative — actual typedefs land in evo under Claude’s PR
typedef EwForecastGenes = {
  var phiDeltas:Map<String, Float>; // keys ⊆ EwPhiParams soft fields
  var samplerBudget:Int;            // 0 = lattice only
  var seed:Int;
  var hostKind:String;              // "lattice" | "mcmc"
}

typedef CoEvolveBundle = {
  var ?forecast:EwForecastGenes;    // optional; null = shared process EwPhiParams
  var trade:StrategyGenome;         // existing five roots + params
}
```

Variation rules (recommendations for Claude):

- Mutate `phiDeltas` with small Gaussian steps + clamp to positive tolerances.
- Never mutate hard-rule constants.
- Cross over forecast genes and trade genes separately (or with a low rate of “pair swap”) so forecast skill and trade exploit can specialize then recombine.
- Parsimony: penalize high `samplerBudget` and large `|phiDeltas|`.

---

## Fitness without letting trade rewrite grammar

| Term | Source | Notes |
|------|--------|-------|
| `sharpe` / equity | existing Fitness | unchanged default |
| `projCoverage` | fraction of realized path in [priceLo,priceHi] over horizon | PIT; after *t* |
| `projCRPS` | when samples>1 | else skip / MAE degeneracy |
| `invSurvive` | when topMass high, price should not breach invalidate early | rewards honest invalidation |
| `countEntropy` prior | optional penalty for chronic ambiguity *if* trade still sizes large | optional descriptor for MAP-Elites |

Hard-rule violations are **impossible** if TradeLogic only consumes host output and host only emits rule-valid counts. Do not add a fitness bonus for “closer to violating W2” — that would smuggle soft pressure into hard territory.

Avoid double-counting: if `EwLattice` soft scores already used θ to pick the preferred count, `projScore` should score **forward predictive quality**, not re-reward the same fib soft hits.

---

## Working-example MVP (smallest demo)

**Goal:** Show co-evolution of a projection-cloud *consumer* + trader, without full MCMC.

### Slice 0 — contracts (this pass)

- [x] `musescript/ew/` docs + `ForecastCloud` + `EwForecastHost`
- [ ] Pointer from `indicators/ew/handbook/BRAINSTORM.md`

### Slice 1 — LatticeForecastHost adapter (ew package; small)

- Implement `LatticeForecastHost implements EwForecastHost` wrapping `EwLattice` / `EwProject` / `EwInvalidation` (still importing from `indicators.ew` until promote).
- Unit test: synthetic impulse → non-NaN band + invalidate price.
- **No** EvolutionEngine changes.

### Slice 2 — Claude evo boundary

- Provider maps host cloud → `SProj` fields.
- One seed genome: enter long when `prob_up` or mid > close and `spread` < param; exit on invalidate proximity or cross.
- Fitness: PnL + simple coverage term, default-off flag.
- Parity: genomes with `forecast == null` match today.

### Slice 3 — Soft φ gene only

- `phiDeltas` applied via `EwPhiParams.clone()` + host `phiKey` for cache.
- Offline finetune pack remains a prior; genes are residual deltas.

### Slice 4 — Tiny MCMC stub (optional)

- Inner MH: propose swap among **already valid** top-K lattice rivals (or valid corrective sibling labels), accept via soft likelihood under θ.
- Same `EwForecastHost` API; `samples` = chain thin count; aggregate bands.
- Still no CYK/CFG engine required.

---

## Mapping existing Muse pieces

| Existing | Role in co-evolve |
|----------|-------------------|
| `EwPhiParams` | Soft θ; gene deltas + finetune prior |
| `EwLattice` / stack | Discrete L candidates; MCMC proposal substrate |
| `EwProject` | Point/band synthesizer → cloud mid/lo/hi |
| `EwInvalidation` | Cloud invalidate + survivability metric |
| `EwHypothesisIndicator` | Chart facade; later call host instead of inline lattice |
| `GeomViz.ForecastBand` | Viz of cloud band (status Projected) |
| `PROJECTION_COEVOLUTION_PLAN` | Generic fan/genome/fitness — Claude implements; EW is first host |
| `Fitness` / NMA / Variation | Claude — consume host at boundary X |

---

## Open questions (defer to Claude + later slices)

1. Is EW a special `ProjSampler` variant or a separate `forecastGenes` root beside generic projections?  
   **Recommendation:** one ProjectionProvider; EW host is a sampler backend so TradeLogic grammar stays unified (`SProj` only).
2. Population eval: always lattice, MCMC on elites only? **Yes** default.
3. Multi-degree clouds: one cloud per degree or nested fields? Start with fine degree; expose `nest` scalar.
