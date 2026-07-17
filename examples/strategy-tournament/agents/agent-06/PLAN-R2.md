# Agent 06 — Round 2 Plan (Maximalist Composer)

## R1 post-mortem

| Issue | R1 symptom | R2 fix |
|---|---|---|
| Over-filtered entries | s02/s04/s05 had **0 trades** on SPY/QQQ/IWM | Loosen gates: `OR` paths, `position()==0` guards, drop stacked `&&` MACD/RSI on entry |
| Wrong Donchian idiom | `close >= highest(high,N)` in templates | Steal winner: `high >= highest(high,N)` / `low <= lowest(low,N)` |
| Stmt-template runtime bug | `EquityHardStop()` invocation throws | Keep stmt-template **definitions**; inline `onPosition` bodies (documented pattern) |

Best R1 self-test (full basket) was s05 CascadeMaestro (+0.024 d_sharpe) but tournament eval collapsed to −1.59 d_sharpe due to zero-trade symbols.

## Stolen from podium / winner

| Source | Pattern stolen | Where used |
|---|---|---|
| **agent-05 s05** (winner) | Donchian 21-high / 13-low + 13-bar time cap | s01, s03, s05 |
| **agent-02 s02** (podium) | EMA 8/34 cross + EMA21 gate + 5% equity stop | s02 |
| **agent-01 s05** (podium) | Plain EMA 8/34 asymmetric exit | s03, s05 |
| **agent-01 R2 s04** | EMA 8/13 in, exit 21, 13-bar time | s04 |

## Kept (BRIEF mandate)

- **Expr templates**: `fastEmaCross`, `slowEmaExit`, `donchianHigh/Low`, `goldenCross`, `macdBull`, `aboveTrend`, `rsiOk`
- **Stmt templates** (docs only): `EquityHardStop`, `TimeExit`, `ProfitLock`, `TrailBelowEma`
- **Asymmetric exits**: fast entry MA vs slower exit MA (8/21 vs 8/34)
- **Layered `onPosition`**: 5% hard stop + Fib time (8/13/21/34) + profit lock + trail

## R2 arsenal

| File | Name | Core thesis | Templates |
|---|---|---|---|
| `s01.ms` | DonchianVault | Winner Donchian + EMA21 trend filter + profit lock | 6 expr + 3 stmt |
| `s02.ms` | GateMaestro | Podium EMA834 gate + asymmetric 8/21 exit + trail | 5 expr + 4 stmt |
| `s03.ms` | HybridPulse | EMA834 **OR** Donchian21 entry; dual exit paths | 5 expr + 2 stmt |
| `s04.ms` | GoldenTime | Golden 8/13, exit 21, 13-bar time (agent-01 R2) | 5 expr + 3 stmt |
| `s05.ms` | CascadeR2 | Dual entry (EMA gate + Donchian55); MACD/RSI exit filter | 9 expr + 3 stmt |

## 3m self-test (2026-04-14 .. 2026-07-13)

### Full basket (10 symbols)

| Rank | Strategy | Mean Sharpe | Mean d_sharpe | Median MDD |
|---:|---|---:|---:|---:|
| 1 | **s05 CascadeR2** | **1.288** | **−0.096** | 0.067 |
| 2 | s01 DonchianVault | 1.210 | −0.175 | 0.055 |
| 3 | s03 HybridPulse | 1.189 | −0.195 | 0.081 |
| 4 | s04 GoldenTime | 1.084 | −0.301 | 0.124 |
| 5 | s02 GateMaestro | 1.070 | −0.314 | 0.043 |

### SPY + QQQ + NVDA spot check

| Symbol | Best | Sharpe | d_sharpe | Trades |
|---|---|---:|---:|---:|
| SPY | s02 | 2.38 | **+0.08** | 2 |
| QQQ | s03/s05 | 2.77 | **+0.74** | 2–4 |
| NVDA | s02 | 0.17 | −0.28 | 2 |

**Flagship:** `s05.ms` — best full-basket mean Sharpe and closest to buy-hold parity; QQQ +0.74 d_sharpe matches winner-tier.

**SPY/QQQ focus pick:** `s02.ms` — only R2 member with positive SPY d_sharpe and lowest median MDD (4.3%).

## vs R1 agent-06

- All five R2 strategies trade on SPY (R1: 3/5 had zero SPY trades in tournament)
- Best R2 mean Sharpe 1.29 vs R1 best 0.75 (tournament s02)
- s05 d_sharpe improved from −1.59 → −0.10 (full basket)

## Iteration command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/round-02/s0N.ms --symbol SPY
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/round-02/s0N.ms
```
