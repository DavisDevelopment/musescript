# Agent 06 — Maximalist Composer Plan

## Hypothesis

Layered **EMA trend systems** with **asymmetric exits** (fast entry MA vs slower exit MA) capture the Apr–Jul 2026 bull tape while `onPosition` hard stops and Fib time exits cap tail risk. Expr templates factor reusable cross/trend/MACD gates; risk shells are inlined in `onPosition` (stmt-template *definitions* document the pattern — bare stmt-template invocation currently throws `Cannot call null` in `gene-runner.js`, so shells are duplicated inline).

## Corpus → 3m translation

| OOS corpus edge | Agent adaptation |
|---|---|
| EMA 8/13, exit 21 (`31_ema_8_13_ex21_tx`) | **s01** — golden cross + slow exit |
| EMA 8/34 (`33_ema_8_34`) | **s02** — pure trend ride + SMA55 exit |
| EMA 8/21, exit 34 (`22_fast_ema_slow_exit`) | **s03** — fast/slow asymmetry + 55-bar time stop |
| EMA 13/34 + hard/time (`19_ema_time_hard`) | **s04** — mid-speed cross + 5% / 55-bar shell |
| Composite | **s05** — EMA 8/34 entry, 8/21 exit, MACD/RSI/anchor filters, profit lock |

Fib ladder windows used: **8, 13, 21, 34, 55** (subset of official ladder).

## Risk controls (all strategies)

- **Equity hard stop:** 5–6% `unrealized_pnl` vs `equity`
- **Time stop:** 34 or 55 bars (`bars_in_trade`)
- **Asymmetric exit:** crossunder fast EMA vs slower exit EMA (not symmetric entry pair)
- Boolean composition via `&&` / `||` only

## Iteration loop

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/strategies/s0N.ms --symbol SPY
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/strategies/s0N.ms
```

1. Start from corpus-proven EMA cores (must trade on 62-bar tape).
2. Add filters one layer at a time; reject if `trades == 0` on SPY.
3. Rank on **mean 3m Sharpe** then **mean d_sharpe** across 10 symbols.
4. Keep median MDD ≤ ~0.13.

## Arsenal summary

| File | Core idea | Templates |
|---|---|---|
| `s01.ms` | EMA 8/13 in, exit 21 | `goldenCross`, stmt risk defs |
| `s02.ms` | EMA 8/34 trend | `fastEmaCross`, `aboveTrend`, `atrQuiet` |
| `s03.ms` | EMA 8/21 in, exit 34 | `fastEmaCross`, `slowEmaExit` |
| `s04.ms` | EMA 13/34 + time/hard | `midEmaCross` |
| `s05.ms` | Cascade: 8/34 in, 8/21 out, multi-filter | 7 expr + 3 stmt templates |

## 3m self-test leaderboard (2026-04-14 .. 2026-07-13)

| Rank | Strategy | Mean Sharpe | Mean d_sharpe | Median MDD |
|---:|---|---:|---:|---:|
| 1 | **s05** CascadeMaestro | **1.408** | **+0.024** | 0.078 |
| 2 | s03 FastSlowExit | 1.212 | −0.173 | 0.129 |
| 3 | s02 Ema834Guard | 1.184 | −0.201 | 0.111 |
| 4 | s01 GoldenVault | 1.084 | −0.301 | 0.124 |
| 5 | s04 Ema1321Hard | 1.033 | −0.352 | 0.127 |

**Flagship:** `s05.ms` — only arsenal member with positive mean excess Sharpe vs buy-hold on the official basket; strongest single names: AMD (+0.65 d_sharpe), AMZN (+0.66), GOOGL (+0.48), NVDA (+0.11).

## SPY / QQQ / NVDA spot check

| Symbol | Best | Sharpe | d_sharpe |
|---|---|---:|---:|
| SPY | s02/s03/s04 (tie BH) | 2.30 | 0.00 |
| QQQ | s05 | 2.09 | **+0.06** |
| NVDA | s04 | 0.54 | **+0.09** |
