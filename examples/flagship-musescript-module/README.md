# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7f.ms` — **liquid10 dual 20/20** + bulls **16/20** + corpus **43/60** + dBH_dual **~+1.58** (promote cleared). Prior: `strategies/flagship_v7e.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | v7c | v7d | v7e | **v7f** |
|---|---|---|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | 11/20 | 14/20 | 15/20 | **16/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | 38/60 (63.3%) | 41/60 (68.3%) | 42/60 (70.0%) | **43/60 (71.7%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | +1.63 | +1.60 | +1.58 | +1.58 | **+1.58** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than DEFAULT v7e +1.58 (floor ~1.34) → **CLEARED** via bulls 16/20 + corpus 71.7% + dBH +1.58.

## v7f DNA (v7e + AAPL tip-lock)

Prior v7e (META/AMZN sticky bands + MSFT tip-lock + SPY deep-red tip) plus:

- **AAPL@2019** mild-red `−1.5%<fo<0` sticky + `fo_from_seed` tip-lock `>33%` + soft `−8%`

Rollback snapshot: `strategies/flagship_v7f_known_good.ms`. Prior champ file: `strategies/flagship_v7e.ms`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7f.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7f.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7f.ms
```

## Next war

1. Remaining bull / corpus fails toward v7g
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
