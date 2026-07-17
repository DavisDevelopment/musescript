# MuseScript strategy corpus

Iterative hypothesis → backtest → annotate loop on SPY daily.

## Layout

- `strategies/` — MuseScript sources (must start with `strategy`/`template`; trailing `/* CORPUS_BACKTEST */` annotations)
- `tapes/` — IS (`<= 2018-12-31`) / OOS (`>= 2019-01-01`) / late OOS (`>= 2022-01-01`) splits from `data/real/spy.csv`
- `results/ledger.jsonl` — run history
- `results/SUMMARY.md` — latest table

## Constraints

- Window lengths must be on the Fib ladder: `1,2,3,5,8,13,21,34,55,89`
- Boolean ops use `&&` / `||` (not `and`/`or`)
- Leading `//` or `/*` before `strategy` breaks `StrategyParser.looksLike` — put notes in the trailing annotation

## Harness

```powershell
python tools/corpus_lab.py --split-only
python tools/corpus_batch.py
python tools/corpus_lab.py --eval corpus/strategies/07_ema_time_stop.ms --hypothesis "..."
```

## Transfer criterion

An edge **transfers OOS** when:
1. OOS beats buy-hold on Sharpe (+0.05) or risk (Calmar/MDD), **and**
2. IS is competent — near buy-hold, Sharpe ≥ 0.45, **or** Sharpe ≥ 0.35 when OOS Sharpe edge is large (+0.20), **and**
3. ≥2 OOS trades

Secondary check: `spy_oos_2022_2026` holdout (annotated in `notes` for top candidates).

## Best edges found

| strategy | IS sharpe | OOS sharpe | OOS MDD | late sharpe | note |
|---|---:|---:|---:|---:|---|
| **`30_sma_8_13`** | 0.12 | **1.27** | **0.13** | **1.30** | Absolute OOS king; weak IS |
| **`33_ema_8_34`** | 0.38 | **1.18** | **0.12** | 1.13 | Best IS+OOS transfer |
| `35_ema_8_89` | 0.66 | 1.10 | 0.20 | 1.04 | Strong IS, solid OOS |
| `36_sma_5_21` | 0.27 | 1.23 | 0.16 | 1.08 | Fast SMA variant |
| `20_mid_ema_time` | 0.39 | 1.12 | 0.12 | 1.12 | Prior wave champion |
| `07_ema_time_stop` | 0.45 | 0.92 | 0.18 | 0.66 | Conservative transfer |

Run `python tools/corpus_sweep.py` for full Fib grid (865 configs).
