# EW Handbook implementation progress

| Ch | Status | Artifacts | Refactors forced |
|----|--------|-----------|------------------|
| 1 Broad Concept | done | ImpulseRules motive/impulse/diagonal; CorrectiveRules zigzag/flat/triangle stub; multi-window EwLattice; EwPhiParams; ch01_*.pseudo.md | Tip-only lattice → sliding windows; W3-beyond-W1 + W4≤100%W3 explicit |
| 2 Guidelines | done | EwGuidelines.hx; lattice multiplies guideline scores | Confirmed Ch1 did not hard-gate guidelines |
| 3 φ Math | done | EwPhiParams identities; SoftScores.bestFibHitParams; RatioTables.EW_PHI_CORE | Soft hits parametrized |
| 4 Ratio Analysis | done | EwRatioTargets; wave-aware EwProject; PhiParamsDump | fromLastLeg uses params |
| deepen correctives | done | flat regular/expanded/running; real triangle a-e; double zigzag W-X-Y | lattice windows 4/6/8 |
| degree nesting | done | SwingGraphStack (fine/coarse thresholds → degree 0/1); parentIdx linkage; EwLattice.rebuildStack + nestingSoft; EwHypothesis parent fields; indicator degree/parent scalars | single SwingGraph → two-threshold stack |
| invalidation levels | done | EwInvalidation (label+pivots); EwHypothesis.invalidatePrice/Bar; lattice fill; indicator scalars + ZoneKind.Invalidation zone | compose-only — no Impulse/CorrectiveRules rewrite |

Tests: `TestEwHandbookCh01` (Ch1–4 + deepen + invalidation), `TestEwDegreeNesting` (stack + nesting).

### B7 invalidation API sketch
```
EwInvalidation.forLabel(label, pivots, offset) → {price, bar}
  impulse5 / diagonal_*  → W1 origin (p0)     // kill beyond start of W1
  zigzag / double_zigzag → A/W origin (p0)    // B beyond start of A
  flat_*                 → C tip (p3)         // still-corrective vs new motive
  triangle               → A tip (p1)         // beyond widest actionary
EwInvalidation.softNextW4(pivots, offset)     // completed-5 soft forward (W4 end)
EwLattice makeHyp fills invalidate* from pivots
EwHypothesisIndicator exposes invalidatePrice / invalidateBar (+ thin Invalidation zone)
```