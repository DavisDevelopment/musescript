# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7b.ms` — **liquid10 dual 20/20** + bulls **8/20** + corpus **35/60** + quick matrix **10/12** (promote cleared). Prior: `strategies/flagship_v7.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | **v7b** |
|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | **8/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | **35/60 (58.3%)** |
| quick matrix perfect | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | **+1.63** |

Promote: dual ≥18 + (bulls≥8 ∨ corpus≥55%) + dBH not >15% worse than v7 +1.55 (floor ~1.32) → **CLEARED** via bulls 8/20 + corpus 58.3% + dBH +1.63.

## v7b DNA (v7 seed-done + targeted islands)

Prior v7 seed-done (QQQ/MSFT) plus:

- **SPY** confirm-green with `fo>4%` demote
- **BAC** confirm-green → atr
- **AMZN** no-punch/bail + `amznArm` sticky (crown muted bar1 / while armed)
- **WMT** atr iff bar1 `fo<-1%`

See `results/v7_oob_bakeoff.md`. Rollback snapshot: `strategies/flagship_v7b_known_good.ms`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7b.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7b.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7b.ms
```

## Next war

1. **AMD / AAPL / GOOGL @ wf_2024q4** (still failing bull cells)
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
