# Ch4 — Ratio Analysis & Fibonacci Time Sequences

## Projectors (EwRatioTargets)
```
wave2RetracePrices(p0,p1)     ← params.w2RetraceTargets
wave4RetracePrices(p2,p3)     ← params.w4RetraceTargets
wave3ExtensionPrices(...)     ← params.w3ExtTargets * W1 from W2 tip
wave5Targets(...)             ← params.w5ExtTargets
zigzagCTargets(...)           ← params.zigCTargets via RatioEngine.projectLeg
timeBars(from, leg)           ← params.timeMultipleTargets
geometricBlend(high,low)      ← Louisli high^e * low^(1-e)
```

## EwProject
```
fromLastLeg → φInv / φExt1618 beyond tip
fromHypothesis(impulse5|diagonal) → W5 target band
fromHypothesis(zigzag|flat) → C target band
```

## Finetune export
`PhiParamsDump.toMap` / `applyMap` — offline only.

## Re-audit
`fromLastLeg` no longer hardcodes 0.618/1.618 — uses EwPhiParams.
Form analysis still precedes ratios (Bolton) — lattice hard rules unchanged.
