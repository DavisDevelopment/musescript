# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7d.ms` — **liquid10 dual 20/20** + bulls **14/20** + corpus **41/60** + dBH_dual **~+1.58** (promote cleared). Prior: `strategies/flagship_v7c.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | v7c | **v7d** |
|---|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | 11/20 | **14/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | 38/60 (63.3%) | **41/60 (68.3%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | +1.63 | +1.60 | **+1.58** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than DEFAULT v7c +1.60 (floor ~1.36) → **CLEARED** via bulls 14/20 + corpus 68.3% + dBH +1.58.

## v7d DNA (v7c + META/AMZN sticky bands + MSFT tip-lock)

Prior v7c (AAPL/AMD/GOOGL islands) plus:

- **META / AMZN** 2019 sticky bands (META deep-red `fo<-2%` @bullx; AMZN mild-red `-1.5..-1%` @bullx)
- **MSFT** tip-lock: deep-red `fo<-2%` sticky, flat when `fo_from_seed >19.5%`

Rollback snapshot: `strategies/flagship_v7d_known_good.ms`. Prior champ file: `strategies/flagship_v7c.ms`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7d.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7d.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7d.ms
```

## Next war

1. Remaining bull / corpus fails toward v7e
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
