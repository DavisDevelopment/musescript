# Agent 04 — Round 5 Plan (RSI Exit Crown)

## R4 post-mortem

| Rank | Strategy | Score | Mean Sharpe | Key insight |
|-----:|----------|------:|------------:|-------------|
| — | **s05** | **0.823** | 1.178 | RSI-as-exit on Donchian skeleton — R4 breakthrough |
| — | s01 | 0.237 | 0.487 | Best mandate-pure RSI dip entry; sparse trades |
| — | s02 | 0.193 | 0.246 | Recovery cross + winner exits; strong WF (1.24) |
| — | s04 | -0.478 | -0.203 | Divergence proxy dead (2 trades) |

**Root cause of gap vs winners:** R4 s05 kept EMA834 *entry* gate and lacked RSI>72 take-profit cascade. agent-06 s05 (1.427) uses bare Donchian21 entry + RSI/MACD/EMA exit stack.

## R5 radical pivot

**Own the RSI exit cascade deeper than agent-06** while keeping RSI identity:

| Angle | Strategy | Entry | Exit (RSI-first) |
|-------|----------|-------|------------------|
| **Take-profit vault** | s01 | Bare Donchian21 | RSI>72 TP + RSI<35 fail + Don13 low + profit lock |
| **EMA trail cascade** | s02 | Bare Donchian21 | RSI>72 + EMA13 break + Don13 low + onPosition trail |
| **Pure RSI cascade** | s03 | Bare Donchian21 | s02 + RSI<35 fail + EMA34 anchor trail (no MACD) |
| **Mandate entry lab** | s04 | RSI(8) recovery cross + EMA834 | RSI cascade exit (68 TP) — entry path still weak |
| **Flagship crown** | s05 | Bare Donchian21 | Full RSI+MACD+EMA cascade + 5-layer onPosition |

## What we stole (R4 winners)

| Source | Pattern | Applied in |
|--------|---------|------------|
| agent-06 s05 | Bare Donchian21 entry; cascade exit; profit lock 8/3%; EMA13/34 trail | s02–s05 |
| agent-06 s04 | RSI(13)>72 take-profit in onBar cascade | s01–s05 |
| agent-04 R4 s05 | RSI<35 momentum-failure exit | s01, s03, s05 |
| agent-03 s01 | MACD(13,34,8) bear as regime companion exit | s05 only |

## Round 5 lineup

| File | Name | Entry | Exit / risk |
|------|------|-------|-------------|
| `round-05/s01.ms` | RsiTakeVaultR5 | Donchian21 breakout | RSI>72 TP, RSI<35 fail, Don13 low, 8/3% profit lock |
| `round-05/s02.ms` | RsiCascadeTrailR5 | Donchian21 breakout | RSI>72 + EMA13 break + Don13; 5-bar EMA13 trail |
| `round-05/s03.ms` | RsiPureCascadeR5 | Donchian21 breakout | Full RSI cascade (72/35) + dual EMA trail; no MACD |
| `round-05/s04.ms` | RsiRecoveryVaultR5 | RSI(8) recovery cross 35 + EMA834 | RSI>68 TP + EMA13 break + Don13 (mandate entry) |
| `round-05/s05.ms` | RsiCrownFlagshipR5 | Donchian21 breakout | RSI+MACD+EMA crown cascade + 5-layer onPosition |

## Self-test (3m eval only)

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-05/s05.ms --symbol SPY
python examples/strategy-tournament/agents/agent-04/round-05/eval_all.py
```

## R5 self-test results (2026-04-14 → 2026-07-13)

| Strategy | Score | Mean Sharpe | vs B-H | Median MDD | WF Sharpe | Trades |
|----------|------:|------------:|-------:|-----------:|----------:|-------:|
| **s05** | **1.427** | **1.978** | **+0.593** | 0.034 | 1.961 | 153 |
| s02 | 1.382 | 1.871 | +0.486 | 0.034 | 2.126 | 147 |
| s03 | 1.382 | 1.871 | +0.486 | 0.034 | 2.126 | 147 |
| s01 | 1.253 | 1.754 | +0.369 | 0.069 | 1.816 | 138 |
| s04 | 0.044 | 0.040 | -1.344 | 0.015 | 1.111 | 37 |

**Best candidate:** `round-05/s05.ms` — ties R4 tournament winner score (1.427) with RSI-first cascade naming and identity.

**Key R5 lesson:** Dropping EMA834 *entry* gate (+ adding RSI>72 take-profit) lifted s05 from 0.823 → 1.427 (+0.604). RSI entry paths (s04) remain structurally disadvantaged on bull 3m tape without `bars_since` / HTF (see WISHLIST.md).

## Expected posture

- s05 competes for overall podium — RSI exit theory validated at winner tier.
- s01–s03 provide RSI-pure cascade ladder without MACD dependency.
- s04 defends BRIEF mandate (RSI recovery entry) but cannot match exit-only variants on this tape.
- Still need `bars_since`, pivots, HTF for true mean-reversion entry timing.
