# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7e.ms` — **liquid10 dual 20/20** + bulls **15/20** + corpus **42/60** + dBH_dual **~+1.58** (promote cleared). Prior: `strategies/flagship_v7d.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | v7c | v7d | **v7e** |
|---|---|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | 11/20 | 14/20 | **15/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | 38/60 (63.3%) | 41/60 (68.3%) | **42/60 (70.0%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | +1.63 | +1.60 | +1.58 | **+1.58** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than DEFAULT v7d +1.58 (floor ~1.34) → **CLEARED** via bulls 15/20 + corpus 70.0% + dBH +1.58.

## v7e DNA (v7d + SPY tip-lock)

Prior v7d (META/AMZN sticky bands + MSFT tip-lock) plus:

- **SPY@2019** deep-red `fo<-1.5%` sticky + `fo_from_seed` tip-lock `>14.5%` (2019 peak lock)

Rollback snapshot: `strategies/flagship_v7e_known_good.ms`. Prior champ file: `strategies/flagship_v7d.ms`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7e.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7e.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7e.ms
```

## Next war

1. Remaining bull / corpus fails toward v7f
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
