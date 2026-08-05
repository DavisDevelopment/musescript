# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v6l.ms` — **liquid10 dual 10/10** + quick matrix **10/12**

## Scoreboard (causal next-open, 10 bps)

| Cell | v6j | v6k | **v6l** |
|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | weak | **10/10** | **10/10** |
| liquid10 × eval × position | weak | weak | **10/10** |
| index3 × eval × position | weak | weak | **3/3** |
| quick matrix perfect | 8/12 | 8/12 | **10/12** |

The only imperfect quick-matrix cells: `* × eval × swing` (IWM seed structural).

## v6l DNA (on top of v6k)

**Quality-funnel fill budget** — `PathLatch nFill` on SPY/QQQ: fills 1–5 free, 6–8 require `atrSig`, then sealed. Matrix position max written into runtime DNA.

Plus v6k: bearChurn · iwmPulse · googlEarly · sticky IWM · AAPL trail · MSFT flip.

See `results/v6l_funnel_champion.md`.

## Commands

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v6l.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v6l.ms
```

## Next war

1. **v7 OOB bakeoff** — five wild candidates in `results/v7_oob_bakeoff.md`; run `harness/v7_bakeoff.py`
2. Corpus bulls — twin genome `flagship_bull.ms` via `harness/bull_score.py` (champ stays v6l)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
4. Keep 10/12 while cleaning non-bull available fails (JPM/BAC/XOM/TSLA)
