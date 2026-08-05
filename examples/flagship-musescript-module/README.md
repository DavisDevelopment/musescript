# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7.ms` — **liquid10 dual 20/20** + bulls **6/20** + quick matrix **10/12** (promote cleared)

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7_meta_kelly | **v7** |
|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 4/20 | **6/20** |
| quick matrix perfect | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.54 | **+1.55** |

Promote: dual ≥18 + (bulls≥6 ∨ corpus≥55% ∨ matrix>10/12) + dBH within 15% of +1.49 → **CLEARED** via bulls 6/20.

## v7 DNA (meta_kelly + mild-bull seed)

**Causal seed-ride for QQQ + MSFT** — bar1 FlagshipBull seed; demote if fromOpen vs seed `>4%` or `<-5%`; successful 13-bar timeout / profit-lock seals `doneGate` (no crown re-churn). IWM sticky island untouched. SPY stays meta crown (seed broke 2022 dual).

See `results/v7_oob_bakeoff.md`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7.ms
```

## Next war

1. **SPY @ 2024** without losing SPY @ 2022 dual
2. Corpus ≥55% (banks / available fails)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
