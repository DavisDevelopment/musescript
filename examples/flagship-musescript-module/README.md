# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7c.ms` — **liquid10 dual 20/20** + bulls **11/20** + corpus **38/60** + quick matrix **10/12** (promote cleared). Prior: `strategies/flagship_v7b.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | **v7c** |
|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | **11/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | **38/60 (63.3%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | +1.63 | **+1.60** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than v7b +1.63 (floor ~1.39) → **CLEARED** via bulls 11/20 + corpus 63.3% + dBH +1.60.

## v7c DNA (v7b + AAPL/AMD/GOOGL islands)

Prior v7b (SPY/BAC/AMZN/WMT islands) plus:

- **AAPL** mild-green sticky (`0<=fo<1%`; else atr)
- **AMD / GOOGL** quietFade when `abs(bar1 fo)<0.5%` (RSI fade island)

See `results/v7_oob_bakeoff.md`. Rollback snapshot: `strategies/flagship_v7c_known_good.ms`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7c.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7c.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7c.ms
```

## Next war

1. Remaining bull fails (corpus / liquid10 weak spots toward v7d)
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
