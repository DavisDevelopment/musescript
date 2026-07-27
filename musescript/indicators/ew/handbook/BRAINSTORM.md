# EW handbook — direction palette

**Date:** 2026-07-27  
**Baseline:** Ch1–4 lattice (`8274913`) + deepen correctives (`e9a8757`) + degree nesting (`a524e71`) + φ finetune (`523ac8a`).  
**Hard rules stay non-learnable.** Soft scores / projection mixes live in `EwPhiParams`.

## Package promotion + MCMC co-evolve (read first)

EW is promoting **out of** `indicators` into infra package **`musescript/ew/`**:

| Doc | Path |
|-----|------|
| Architecture (paper × Muse × evo) | [`../../../ew/ARCHITECTURE.md`](../../../ew/ARCHITECTURE.md) |
| ForecastFn × TradeLogic brainstorm | [`../../../ew/BRAINSTORM_COEVOLVE.md`](../../../ew/BRAINSTORM_COEVOLVE.md) |
| Move plan | [`../../../ew/PROMOTE_PLAN.md`](../../../ew/PROMOTE_PLAN.md) |
| Stub contracts | `musescript/ew/ForecastCloud.hx`, `EwForecastHost.hx` |

**Evo forecasting wiring** (EvolutionEngine / Fitness / Variation / `SProj`): owned by parallel Claude session — integrate at `EwForecastHost` → ProjectionProvider boundary. Do not duplicate that work in handbook slices.

Siblings (parallel, not owned here): **B7 invalidation levels**, **C11 parent GeomViz overlay**.

---

## A. Expand pattern coverage — THIS SLICE

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Real corrective family: expanded/running flats, W-X-Y / W-X-Z | DONE | softScoreFlat by kind; double_three WXZ; double_zigzag kept |
| 2 | Triangle a–b–c–d–e maturation (degree-aware boundaries) | DONE | triangleKind contracting/expanding; degree tol on edges |
| 3 | Diagonal variants: ending vs leading as separate labels | DONE | `diagonal_ending` / `diagonal_leading` |
| 4 | Truncation / failure (truncated fifth) + cautious projection | DONE | `impulse5_trunc` + shrinkBand |
| 5 | Extension ID: extended-1/3/5 biasing W4 territory & W5 targets | DONE | `impulse5_ext{1,3,5}`; nestingSoft W4 shallow; wave5TargetsExt |

**Files:** `CorrectiveRules`, `ImpulseRules`, `EwPhiParams`, `EwLattice`, `EwProject`, `EwRatioTargets`, `EwHypothesisIndicator`, tests, `PROGRESS.md`.

---

## B. Competing counts (alternates as real rivals)

| # | Item | Status | Owner |
|---|------|--------|-------|
| 6 | Stronger hypothesis identity (window × type × degree × parent) | PLANNED | — |
| 7 | Invalidation levels (“dead if price does X”) | SIBLING | parallel agent |
| 8 | Guideline feature vectors for finetune | PLANNED | — |

---

## C. Degree nesting (beyond fine/coarse)

| # | Item | Status | Owner |
|---|------|--------|-------|
| 9 | 3+ thresholds on `SwingGraphStack` (JIT-stable) | PLANNED | — |
| 10 | Calendar degree naming (Grand Supercycle → Subminuette) | PLANNED | — |
| 11 | Parent overlay (GeomViz / Mederos) | SIBLING | parallel agent |

---

## D. Proportional / math confidence

| # | Item | Status |
|---|------|--------|
| 12 | CPD + value-based anchors for pivot / nesting confidence | PLANNED |
| 13 | `ScaleValidityGate` → real MF-DFA-ish φ legitimacy gate | PLANNED |

---

## E. Finetune (theory-compatible)

| # | Item | Status |
|---|------|--------|
| 14 | Soft-only: weights / tols / guideline weights / projection mixes | PARTIAL (`FINETUNE.md`) |
| 15 | Projection-quality loss (+ invalidation survivability) | PLANNED |

---

## F. Risk & cycles (meta priors)

| # | Item | Status |
|---|------|--------|
| 16 | LPPL as soft prior on hypothesis selection | PLANNED |
| 17 | SSA/MESE as time-plausibility prior (not replacing EW time) | PLANNED |

---

## G. Viz / product

| # | Item | Status |
|---|------|--------|
| 18 | Confidence-coded geometry (opacity ∝ score × invalidation distance) | PLANNED |
| 19 | Alternate-count UI (Preferred vs Top alternates) | PLANNED |

---

## Constraints (all slices)

- JIT: indexed loops; no `Array.shift` on hot path.
- Hard structural rules never read learnable floats for boolean gates.
- Do not break GeomViz shape contracts (`PivotMarkSet` / `LabelSet` / `ForecastBand` / `ZoneSet`).
- Do not implement B7 or C11 in this slice.
