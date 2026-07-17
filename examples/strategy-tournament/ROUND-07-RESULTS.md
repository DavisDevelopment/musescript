# Round 7 — Crypto + FX Results (causal)

Eval: **2026-04-14 → 2026-07-13** · execution: **next-open** · 5 crypto + 5 FX

## Eligible winner

**agent-03 / s03.ms** — MacdRisingEntry  
Score **0.511** | traded Sharpe **0.055** | vs BH* **+0.912** | **10/10** symbols · **62** trades · WF **0.124**

Entry: `rising(macd.hist, 3) && hist > 0`  
Exit: hist < 0 / MACD crossunder + `falling(hist, 3, minBars=5)` + 8% stop

## Legacy score trap (disqualified)

Raw/legacy scoring crowned **agent-05 / s05** at **0.705** with **2 trades on USDJPY only** (cash everywhere else). Negative buy-and-hold Sharpes make flat cash look like skill. Same pattern: agent-04 legacy **0.672** with **0 crypto trades**.

From Round 8 onward, official ranking uses:

- traded-only Sharpe / vs-BH (zero-trade symbols do not farm excess)
- eligibility: ≥4 active symbols, ≥8 trades, ≥1 crypto **and** ≥1 FX
- probes (`_probe*.ms`) are not scored

## Eligible podium

| # | Agent | Strat | Score | Legacy | Active | Trades | Edge |
|---:|---|---|---:|---:|---:|---:|---|
| 1 | agent-03 | s03 | **0.511** | 0.462 | 10 | 62 | rising hist entry + minBars exit |
| 2 | agent-02 | s01 | 0.429 | 0.379 | 10 | 57 | EMA834 + SMA21 OR-broaden |
| 3 | agent-03 | s01 | 0.419 | 0.361 | 10 | 55 | MACD companion variant |
| 4 | agent-02 | s04 | 0.404 | 0.354 | 10 | 61 | trend filter sharpen |
| 6 | agent-01 | s05 | 0.348 | 0.420 | 7 | 24 | selective EMA834 + rising spread |

## Domain meta (R7)

- Equity R6 RSI crown dies here (BTC next-open Sharpe **−1.71**)
- Selectivity without participation is not an edge — it is cash
- MACD **rising hist** as *entry* works better on crypto/FX than equity-cycle MACD entry gates
- FX needs softer Donchian gates; strict don21 → 0 EUR trades for several agents
- Stmt templates must be defined in-file; CRLF still crashes gene-runner

## Language

Continue updating `WISHLIST.md`. Open items: exit-layer fire diagnostics, `partial_flat`, `bars_since`, volume helpers.
