# Ch3 — Historical & Mathematical Background (φ)

## Identities → EwPhiParams
```
phi = 1.6180339887
phiInv = 1/phi = 0.6180339887
oneMinusPhiInv = 1 - phiInv = 0.382…
phiSq = phi² = 2.618…
phi * phiInv = 1
phiInv² = 0.382
```

## SoftScores.bestFibHitParams
Reads targets from EwPhiParams when provided; handbook defaults otherwise.

## RatioTables.EW_PHI_CORE
Mirror table for non-EW consumers; runtime EW prefers `EwPhiParams.current()`.

## Re-audit
No Ch1 hard rules changed. Soft hits no longer bury 0.618 literals in ImpulseRules/CorrectiveRules (use param tables).
