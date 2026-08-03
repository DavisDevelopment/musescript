# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v5h.ms` (symbol_is lifts + causal gates + v4 crown)

## Scoreboard (causal next-open, 10 bps)

| Cell | v0 | v1 | v2 | v3 | v4 | v5h |
|---|---|---|---|---|---|---|
| liquid10 × eval_3m × any | 5/10 | 6/10 | 7/10 | 7/10 | 7/10 | **8/10** |
| liquid10 × wf_2022q1 × any | 0/10 | 8/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| quick matrix perfect cells | 0/12 | 1/12 | 2/12 | 4/12 | 4/12 | **4/12** |

### Still weak (eval_3m)
**IWM, MSFT.** AAPL cleared via `symbol_is("AAPL")` → atr sleeve (`d≈+1.84`).
- IWM: pure seed PASSes eval / FAILs 2022; vol-gated hybrid still flaps
- MSFT: pure flip PASSes eval / FAILs 2022; roc55 gate rarely latches ceiling DNA

## v5h DNA

1. **AAPL** — always ATR thrust sleeve (`trail` + soft ATR exits)
2. **IWM** — sticky when `volPct < calmCut`, else v4 crown
3. **MSFT** — flip when `roc55 < deepCut`, else v4 crown
4. **Else** — full v4 crown / PathLatch branched exits
5. Relies on Claude's `symbol_is` / `trail` / `count_true` lang batch (2026-08-03)

### Sibling cuts (not champion)
- `flagship_v5.ms` — pure causal router + hysteresis (7/10, kept for research)
- `flagship_v5s.ms` — ungated symbol sleeves (10/10 eval, **8/10** 2022 — rejected)

## Compiler note

`ClassStrategyLower` now skips non-leaf `muse.Strat` bases, and JS/interp take the **last** `StrategyDecl` only. Previously stitched `FlagshipRisk` merged its `onPosition` into every strategy in the file (seed holds died at `timeBars=13`).

## Killed ideas

| Idea | Why dead |
|---|---|
| Regime as entry veto | Cash on 2022, under-participate vs BH |
| Naive long+short dual | Nukes bull tape |
| Global bar-1 seed hold | PASSes IWM; BH-ties SPY/QQQ/NVDA |
| Softmax path picker | 0 trades (calm mass wins) |
| Ungated ATR / mutex ATR-primary | Loses 2022 10/10 |
| Weak-tape short sleeve in v4 | MSFT dBH flips; SPY/QQQ/AMD bleed out |

## Commands

```powershell
haxe build-cli.hxml

python examples/flagship-musescript-module/harness/eval.py --check
python examples/flagship-musescript-module/harness/eval.py --eval
python examples/flagship-musescript-module/harness/eval.py --matrix --quick

python examples/flagship-musescript-module/harness/family_bakeoff.py
python examples/flagship-musescript-module/harness/ceiling_ensemble.py
python examples/flagship-musescript-module/harness/score_probe.py strategies/probes/p_v3_iwm_seed.ms
```

## Ceiling ensemble (research)

```powershell
python examples/flagship-musescript-module/harness/ceiling_ensemble.py
```

Oracle pick among `{v4, iwm_seed, atr_only, macd_one_shot, long_short_flip}`:

| Window | v4 | ceiling |
|---|---|---|
| eval_3m | 7/10 | **10/10** |
| wf_2022q1 | 10/10 | 10/10 |

Lifts: **IWM→iwm_seed**, **AAPL→atr_only**, **MSFT→long_short_flip**.  
See `results/ceiling_ensemble.md` for encode hints. **Next:** causal sleeve router (v5) — no end-of-window look-ahead.

## Next war

1. Latch IWM sticky without 2022 seed-into-crash (bar-1 vs warm-vol decision)
2. Get MSFT flip to fire on eval without nuking 2022 (roc55 alone under-fires)
3. Swing-band turnover on short windows (still the matrix choke)
