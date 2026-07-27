# Ch2 — Guidelines of Wave Formation

Source: PDF Lessons 10–15 (alternation, depth, equality, channeling).

## Soft only (never hard gates)
```
alternationImpulse(W2 sharp XOR W4 sharp) → score
equalityOneFive(|W5|≈|W1| when W3 longest)
depthSoft(retrace → φ targets)
channelSoft(odd-wave linearity proxy)
scoreImpulse = combine(...)
```

## Re-audit of Ch1
- Alternation / equality / depth were NOT hard-gated in Ch1 ✓
- Flat/triangle remain soft-ish stubs ✓
- Diagonal still allows overlap as HARD distinction from impulse ✓

## Params
`alternationWeight`, `equalityOneFiveWeight`, `depthPriorFourthWeight`, `channelWeight`, `throwOverWeight`
