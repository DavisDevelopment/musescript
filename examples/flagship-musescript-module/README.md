# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v4.ms` (path-latched **branched exits**)

## Scoreboard (causal next-open, 10 bps)

| Cell | v0 | v1 | v2 | v3 | v4 |
|---|---|---|---|---|---|
| liquid10 × eval_3m × any | 5/10 | 6/10 | 7/10 | 7/10 | **7/10** |
| liquid10 × wf_2022q1 × any | 0/10 | 8/10 | 10/10 | 10/10 | **10/10** |
| quick matrix perfect cells | 0/12 | 1/12 | 2/12 | 4/12 | **4/12** |

### Still weak (eval_3m)
**IWM, AAPL, MSFT.** AAPL less poisoned under v4 (`d≈-2.1` vs v3 `d≈-3.2`) but not a pass yet.
- IWM: seed probe still the only clear BH-beater
- MSFT: short sleeve nukes SPY/QQQ — parked

## v4 DNA

1. **Entries** — v3 OR-book (crown / gated ATR / weak MACD-rise / MACD zero)
2. **PathLatch** (construct-once) — remembers open sleeve; crown wins mixed opens
3. **Branched exits**
   - `deepGreen` → late RSI fade / donch34 only
   - `path==crown` → `softCrownExit`
   - `atrBook` (ATR latch or non-crown thrust) → `softCrownNoMacd` (no macdBear)
   - bounce/zero → short leash
4. **Losing crown + ATR** → path upgrade to ATR sleeve
5. **Class risk** — deepGreen suppresses time/profit locks

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

1. Encode ceiling router into `flagship_v5` with *causal* features (`atr/close`, `roc(21)`, chop)
2. Hysteresis so sleeve switches don't thrash SPY/QQQ
3. Swing-band turnover on short windows
