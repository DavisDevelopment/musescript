# Ch1 — The Broad Concept (Frost & Prechter / EWI course Lessons 1–9)

Source: `elliott-wave-principle.pdf` (capsule + Lessons 1–9). Re-read after first sketch.

## Hard RULES (non-learnable)

### Motive (5 waves, progress with larger trend)
```
for pivots p0..p5 (W1..W5 tips):
  alternate directions
  |W2| <= |W1|                          # W2 never >100% of W1
  |W4| <= |W3|                          # W4 never >100% of W3
  W3.end beyond W1.end (motive dir)     # W3 always past W1 tip
  |W3| not shortest among |W1|,|W3|,|W5|
```

### Impulse ⊂ Motive
```
  W4 price territory ∩ W1 price territory == ∅   # no overlap
  # (diagonals ALLOW overlap — separate pattern)
```

### Corrective
```
  corrections are never lone fives against larger trend
  zigzag A-B-C (price skeleton): B does not exceed start of A (sharp)
  flat A-B-C: B ≈ start of A (regular) or beyond (expanded) — soft bands in params
```

## Degrees
Nine named degrees (Grand Supercycle … Subminuette). Relative degree matters more than absolute.
Hypothesis carries `degree:Int` (0 = unspecified / working degree).

## Pattern catalog (Ch1 names → labels)
| Label | Structure | Ch1 status |
|-------|-----------|------------|
| impulse5 | 5-3-5-3-5, no overlap | HARD validate |
| diagonal_ending | 3-3-3-3-3, overlap OK | HARD skeleton (wedge soft later) |
| diagonal_leading | 5-3-5-3-5, overlap OK | HARD skeleton |
| zigzag | 5-3-5 sharp ABC | HARD price rules |
| flat | 3-3-5 | HARD skeleton + param bands |
| triangle | 3-3-3-3-3 a-e | STUB detect 5 pivots converging (soft Ch2) |
| double_three / WXY | combinations | STUB label only |

## Guidelines (NOT hard — Ch2)
Alternation, depth to prior 4th, equality of 1&5, channeling, throw-over, extensions preference, personality.

## Lattice
```
scan all windows of 4 pivots → zigzag/flat candidates
scan all windows of 6 pivots → impulse / diagonal candidates
rank by soft×guidelines (Ch2+); keep top-K
prefer interpretation satisfying most guidelines among rule-valid counts
```

## Params used in Ch1 soft bands only
`EwPhiParams.zigzagBMaxRetrace`, `flatBNear`, `flatCBeyond`, Fib soft targets reserved for Ch3–4.

## Re-audit notes
- Prior Muse code treated W2 as "must stay inside [p0,p1]" — equivalent to ≤100% retrace for alternating swings; keep + add explicit W3-beyond-W1 and W4≤100% W3.
- Tip-only lattice must become multi-window (book: multiple valid counts).
- Flats/triangles named in Ch1 but detailed later — stubs OK if gated.
