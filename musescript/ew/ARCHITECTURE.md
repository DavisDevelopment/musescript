# Hierarchical MCMC × Muse EW × evo co-evolution

**Date:** 2026-07-27  
**Status:** Architecture + contracts. No full MCMC this pass.  
**Evo forecasting wiring:** owned by a parallel Claude session — integrate at the boundaries marked below; do not fork that work here.

---

## Paper digest (binding priors)

From *Navigating Ambiguity in Elliott Wave Analysis: A Hierarchical MCMC Framework…*:

| Layer | Paper role | Muse home |
|-------|------------|-----------|
| **Hard grammar** | Non-negotiable: fractal 5+3, impulse rules, diagonal-only overlap, corrective form checks | `ImpulseRules` / `CorrectiveRules` (today under `indicators/ew/`) — **never learnable** |
| **Soft / learnable** | Fib ratios, projection tolerances, guideline weights, regime priors | `EwPhiParams` (+ offline finetune) |
| **Discrete search** | Combinatorial wave labelings / degree nesting / parent–child | `EwLattice` + `SwingGraphStack` (streaming top-K); MCMC inner loop later |
| **Continuous search** | Soft params outer MCMC | Outer MH / finetune / genome `forecastGenes` deltas |
| **Data** | OHLCV-first; pivots via ZigZag/ATR; optional volume/ATR/CPD/MTF as soft priors | `Bar` → `SwingGraph` / stack; CPD/MF-DFA still PLANNED in handbook |
| **Outputs** | Posterior predictive bands, invalidation levels, entropy / nest / dist-to-invalidation | `ForecastCloud` + GeomViz `ForecastBand` / zones; signals **derived**, not primary |

Hierarchical MCMC sketch from the paper:

1. **Outer loop** — propose soft-param vector θ (`EwPhiParams`-shaped).  
2. **Inner loop** — MH over **rule-valid** labelings L \| θ (proposals that preserve grammar; reject invalids at the gate).  
3. **Synthesize** — aggregate accepted (L, θ) → predictive bands + invalidation distribution + UQ scalars.

Muse already has the **gate + soft rank + single-band project** path. MCMC upgrades the lattice from “top-K soft score” to “posterior mass over valid counts.”

---

## Four paper layers → Muse modules

```text
OHLCV bars
    │
    ▼
[1] Data / pivots          SwingGraph, SwingGraphStack, MonoWave, DowTrendFilter
    │                      (streaming indicators / geom — stay hot-path)
    ▼
[2] Wave ID                ImpulseRules, CorrectiveRules, EwLattice.scan
    │                      HARD boolean gates; soft score only after validity
    ▼
[3] Disambiguation         SoftScores × EwGuidelines × EwPhiParams; nestScore
    │                      → later: inner MCMC over valid L; outer over θ
    ▼
[4] Prediction + UQ        EwProject → ForecastCloud; EwInvalidation
                           entropy / topMass / distToInvalidation
                           → TradeLogic / evo policy consumes cloud features
```

### What stays where

| Concern | Streaming indicator | Batch / MCMC | Genome genes |
|---------|---------------------|--------------|--------------|
| Pivot update, ZigZag thresholds | ✅ JIT hot path | optional offline re-pivot | swing-threshold ratio may be a soft gene later |
| Hard rule checks | ✅ | ✅ (acceptance gate) | **forbidden** — not genes |
| Soft φ / guideline weights | read `EwPhiParams.current()` or host pack | outer sampler / finetune | `forecastGenes.phiDeltas` |
| Top-K lattice rebuild | ✅ `EwLattice` | MCMC replaces / augments | sampler budget / seed policy genes |
| Full posterior / CRPS | ❌ too heavy | ✅ fitness / offline | — |
| Entry/exit on cloud fields | thin indicator may emit scalars | — | `tradeGenes` (Claude evo) |

---

## Package layout (target)

```text
musescript/ew/                 ← NEW HOME (this pass: docs + stubs)
  README.md
  ARCHITECTURE.md              ← this file
  BRAINSTORM_COEVOLVE.md
  PROMOTE_PLAN.md
  ForecastCloud.hx             ← typedef + helpers
  EwForecastHost.hx            ← host interface + stub

musescript/indicators/ew/      ← TEMPORARY implementation site
  ImpulseRules, CorrectiveRules, EwLattice, EwProject, …
  handbook/*                   ← theory / progress; pointer to musescript/ew

musescript/indicators/lib/
  EwHypothesisIndicator.hx     ← streaming facade → GeomViz (keeps compiling)

musescript/evo/                ← Claude owns forecast×trade co-evolve wiring
  EvolutionEngine, Fitness, Variation, StrategyGenome, NMA…
```

Promotion moves `indicators/ew/*.hx` → `musescript/ew/` with thin `indicators.ew` typedefs or `@:deprecated` re-exports — see `PROMOTE_PLAN.md`. Registry / GeomViz stay in indicators.

---

## Contracts Claude should consume

### `ForecastCloud` (`musescript.ew.ForecastCloud`)

Probabilistic / band surface at bar *t*. Degenerates cleanly for today’s single `EwProject` band (`samples = 1`, `topMass = 1`, `countEntropy = 0`). Fan fields (`spread`, `probUp`, …) match the reduction vocabulary in repo `PROJECTION_COEVOLUTION_PLAN.md`.

### `EwForecastHost` (`musescript.ew.EwForecastHost`)

```text
onBar(bar, index)     — streaming advance (no-op for pure batch hosts)
cloudAt(t)            — PIT-causal ForecastCloud
topCounts(t, kMax)    — discrete mass for entropy / rivalry
phiKey()              — cache key for soft-param pack
```

**Handoff boundary X (evo):** `ProjectionProvider` resolves EW projections by asking an
`EwForecastHost` (typically `LatticeForecastHost`) and mapping `ForecastCloud` fields → `SProj`
fan reductions (`p50`, `spread`, `prob_up`, `inv`, `entropy`, …). Sampler gene: `PSHost("lattice"|"mcmc")`.

**Do not** teach EvolutionEngine hard EW rules. Hard rules stay inside the host.

### Gene sketch (documentation only — genome schema owned by Claude)

```text
genome {
  forecastGenes?: {
    phiDeltas: Map<String,Float>   // soft EwPhiParams offsets only
    samplerBudget: Int             // inner MH steps / top-K cap (batch)
    seedPolicy: Int                // deterministic MC / MCMC seed
    hostKind: "lattice" | "mcmc"   // default lattice until MCMC exists
  }
  tradeGenes: {                    // existing StrategyGenome roots
    entryLong, entryShort, exit*, size
    // policy may read SProj("ew_0","spread") etc. once Claude wires SProj
  }
}
```

Hard labels / rule thresholds are **not** genes. Soft scores must not be double-counted: if lattice soft score already shaped the cloud, fitness should not also reward the same soft hits as a separate term without an explicit ablation design.

---

## Fitness principles (for Claude’s scorer; documented here)

Reward **both**:

1. **Forecast calibration** — interval coverage / CRPS-skill / invalidation survivability (price does not kill preferred mass prematurely when mass was high).  
2. **Trading PnL** — Sharpe / equity / existing `FitnessResult`.

Constraints:

- Trade fitness **must not** rewrite or soften hard rules.  
- Forecast skill is measured leakage-free (targets after *t* only) — same PIT discipline as `PROJECTION_COEVOLUTION_PLAN.md`.  
- Prefer additive, default-off `projScore` so genomes without EW hosts stay byte-parity.  
- Cap MCMC / K inside fitness; prefer lattice host for population eval, MCMC for elite re-score or offline.

**Evo wiring: boundary X DONE for lattice score path** (`EwForecastHost` → `ProjectionProvider` /
`PSHost` → `SProj` reductions → Fitness `projScore`). Remaining: Expand trading prelude for host
columns, φ gene deltas, MCMC host.

---

## Risks

| Risk | Mitigation |
|------|------------|
| MCMC cost inside every fitness eval | Lattice host default; MCMC elite-only / offline; gene-capped `samplerBudget` |
| JIT / hot path | No MCMC in `MuseIndicator.update()`; indexed loops; no `Array.shift` |
| Repaint | Confirmed vs Forming pivots; clouds tagged; never treat Projected as Confirmed |
| Soft-score double-counting | One soft channel: either host ranking *or* separate guideline loss — document which |
| Parallel evo work collision | This package owns EW surfaces; Claude owns EvolutionEngine / Fitness / Variation |

---

## MVP path (smallest working example)

See `BRAINSTORM_COEVOLVE.md` § MVP. Short version:

1. Adapter: `EwLattice` + `EwProject` + `EwInvalidation` → `ForecastCloud` (`LatticeForecastHost` **done**).  
2. Evo wires policy reads of cloud reductions + optional `projScore` (**done** — `PSHost` + `ProjectionProvider` + `TestEwHostProjection`).  
3. Only then: stub inner MH over **already-valid** lattice rivals (no full CFG/CYK yet).
