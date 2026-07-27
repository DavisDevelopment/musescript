# EW Handbook implementation progress

| Ch | Status | Artifacts | Refactors forced |
|----|--------|-----------|------------------|
| 1 Broad Concept | done | ImpulseRules motive/impulse/diagonal; CorrectiveRules zigzag/flat/triangle stub; multi-window EwLattice; EwPhiParams; ch01_*.pseudo.md | Tip-only lattice → sliding windows; W3-beyond-W1 + W4≤100%W3 explicit |
| 2 Guidelines | done | EwGuidelines.hx; lattice multiplies guideline scores | Confirmed Ch1 did not hard-gate guidelines |
| 3 φ Math | done | EwPhiParams identities; SoftScores.bestFibHitParams; RatioTables.EW_PHI_CORE | Soft hits parametrized |
| 4 Ratio Analysis | done | EwRatioTargets; wave-aware EwProject; PhiParamsDump | fromLastLeg uses params |
| deepen correctives | done | flat regular/expanded/running; real triangle a-e; double zigzag W-X-Y | lattice windows 4/6/8 |

Tests: `TestEwHandbookCh01` (covers Ch1–4 + deepen).
