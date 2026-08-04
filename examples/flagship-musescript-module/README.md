# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v6k.ms` — **liquid10 dual 10/10** + both **2022×swing** cells perfect + matrix **8/12**

## Scoreboard (causal next-open, 10 bps)

| Cell | v6a | v6j | **v6k** |
|---|---|---|---|
| liquid10 × eval_3m × any | 10/10 | 10/10 | **10/10** |
| liquid10 × wf_2022q1 × any | 9/10 | 10/10 | **10/10** |
| liquid10 × wf_2022q1 × swing | — | weak | **10/10** |
| index3 × wf_2022q1 × swing | — | weak | **3/3** |
| quick matrix perfect cells | 4/12 | 8/12 | **8/12** |

## v6k DNA (on top of v6j)

1. **bearChurn** — deep-bear crown scrapes (excl. IWM/MSFT/AMZN/GOOGL) → SPY/QQQ into swing
2. **iwmPulse** — post-sticky mild bounce → IWM 2022 into swing without nuking seed
3. **googlEarly** — `bar<25` rising reload + 6-bar time-stop → GOOGL in swing∩position without eval toxic crosses

See `results/v6k_swing_champion.md`. Prior DNA / sticky bugs: still in git history + `results/v6j_dual_perfect.md`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v6k.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v6k.ms
```

## Next war

1. Cap eval SPY/QQQ at ≤8 trades → unlock eval×position cells → path to **10/12**
2. Raise available×4windows corpus (2019 / 2024q4 bulls)
3. Keep dual 10/10 + 2022 swing while broadening
