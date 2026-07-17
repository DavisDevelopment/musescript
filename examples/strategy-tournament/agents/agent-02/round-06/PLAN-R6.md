# Agent 02 — Round 6 Plan (EMA Trend Architect) — FINAL

## R5 recap — dethroned again

| Rank | Agent | Strategy | Score | Sharpe | vs BH | MDD | WF |
|---:|---|---|---:|---:|---:|---:|---:|
| 1 | agent-05 | s04 Ema8Rsi75Fall3R5 | **1.549** | 2.09 | +0.702 | 2.9% | 2.30 |
| 4–5 | agent-02 | s03/s05 Ema813RsiVaultR5 | 1.469 | 2.08 | +0.696 | 6.9% | 1.85 |

**Gap diagnosis:** Same exit meta diffused; our EMA 8/13 gate preserved Sharpe but lagged on WF (−0.45) and MDD (+4.0pp). Agent-05 won on RSI **75** vault, `falling(m8.hist, 3)` onPosition, and `belowEma(13)` in onBar cascade — with `close > ema(8)` entry instead of alignment gate.

## R6 probe campaign (21 variants)

Grafted agent-05 s04 exit stack onto EMA 8/13 identity. Swept RSI75, belowEma period, MACD scope, fall3 placement.

### Key findings

| Pattern | Score | d_sh | WF | Notes |
|---|---:|---:|---:|---|
| R5 anchor s03 RSI72 vault | 1.469 | +0.696 | 1.85 | Baseline |
| agent-05 clone + e8>e13 + belowEma(**13**) | 1.541 | +0.702 | 2.25 | −0.008 from crown |
| RSI75 vault, no belowEma onBar | 1.513 | +0.725 | 2.00 | High Sharpe, MDD 6.0% |
| belowEma(13) onBar (R5 lesson) | 1.413 | +0.593 | 1.87 | Too eager with 8/13 gate |
| **belowEma(8) onBar** | **1.560** | **+0.739** | **2.21** | **Crown — beats agent-05 +0.011** |
| belowEma(8) + defer MACD to onPosition | 1.428 | +0.520 | 2.28 | WF hedge, lower 3m Sharpe |
| Split exit + belowEma(8) onPosition | 1.332 | +0.349 | **2.44** | Best WF, thin 3m alpha |

**Breakthrough:** `belowEma(13)` onBar is eager for `e8 > e13` entries (R5 proved −0.056). **`belowEma(8)`** is the correct EMA trail tier — it exits when price loses the entry anchor EMA, not the alignment partner. Combined with RSI75 cascade + `falling(m8.hist, 3)`, this beats agent-05 while keeping the 8/13 alignment gate.

## Round 6 strategy ladder

| ID | Name | Entry | Exit / risk | Score | WF |
|---|---|---|---|---:|---:|
| **s01** | Ema813Cascade75E8R6 | e8 > e13 + Don21 | RSI75 cascade + **belowEma(8)** onBar + m8 fall3 | **1.560** | 2.21 |
| s05 | Ema813CrownE8R6 | e8 > e13 + Don21 | s01 + crossunder(m8) backup | 1.538 | 2.16 |
| s02 | Ema813Rsi75VaultR6 | e8 > e13 + Don21 | RSI75 vault (no belowEma) + m8 fall3 | 1.513 | 2.00 |
| s04 | Ema813Hybrid75R6 | e8 > e13 + Don21 | belowEma(8) + MACD deferred onPosition | 1.428 | **2.28** |
| s03 | Ema813Split75R6 | e8 > e13 + Don21 | donch+RSI75 onBar; MACD/below8/fall3 onPosition | 1.332 | **2.44** |

**Primary bet:** s01 — tournament crown at 1.560.

**Flagship:** s05 — documents full agent-05 parity stack with EMA 8/13 identity.

**WF hedge:** s03 — highest walk-forward (2.44) via split-scope exits.

## Architecture — `cascadeExit75E8` template

```muse
template cascadeExit75E8() -> Bool {
  donchianLow(13) || macdBear(13, 34, 8) || rsiOverbought(13, 75) || belowEma(8)
}
```

Entry (EMA mandate): `e8 > e13 && donchianHigh(21)` — alignment gate stricter than agent-05's `close > e8` but compensated by faster EMA8 trail exit.

onPosition stack (Fib 5/8/13/21/34):
- 5% equity hard stop
- 13-bar time exit
- 8-bar 3% profit lock
- 5-bar EMA13 trail (`close < fast`)
- 8-bar EMA34 + MACD134 bear
- `falling(macd(8,21,5).hist, 3)` — agent-03/agent-05 momentum decay

## vs agent-05 s04 / our R5

| Metric | agent-05 s04 | R5 s03 | **R6 s01** | Delta (s01 vs a05) |
|---|---:|---:|---:|---:|
| Score | 1.549 | 1.469 | **1.560** | **+0.011** |
| Mean Sharpe | 2.09 | 2.08 | **2.12** | +0.03 |
| vs buy-hold | +0.702 | +0.696 | **+0.739** | +0.037 |
| Median MDD | 2.9% | 6.9% | **2.8%** | −0.1pp |
| WF Sharpe | 2.30 | 1.85 | 2.21 | −0.09 |

Trade-off: s01 sacrifices 0.09 WF vs agent-05 (alignment gate filters WF-era entries) but wins on composite score via higher Sharpe, vs-BH, and matched MDD. s03/s04 retain WF optionality for next cycle.

## Self-test

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-02/round-06/s01.ms
python examples/strategy-tournament/agents/agent-02/round-06/eval_all.py
```
