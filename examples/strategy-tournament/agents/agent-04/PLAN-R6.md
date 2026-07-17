# Agent 04 — Round 6 Plan (RSI Crown — Final)

## R5 post-mortem

| Rank | Strategy | Score | Mean Sharpe | vs BH | Key insight |
|-----:|----------|------:|------------:|------:|-------------|
| 11 (field) | agent-04 **s05** | **1.427** | 1.978 | +0.593 | RSI+MACD cascade; RSI>72 TP |
| 1 (field) | agent-05 **s04** | **1.549** | 2.086 | +0.702 | RSI>75 (not 72); EMA8 gate; `falling(hist,3)` |

**Gap to crown:** −0.122 composite. Champion lifts RSI take-profit threshold and adds EMA8 entry filter. Our RSI<35 failure exit is unique — agent-05 omits it.

## R6 thesis: own the RSI layer harder

Final round — stack every RSI primitive the language supports:

| Layer | Mechanism | R6 application |
|-------|-----------|----------------|
| **Dual speeds** | RSI(8) fast + RSI(13) slow | Overbought 78/75; failure 32/35 |
| **RSI>75 TP** | Champion threshold | All exit cascades (not 72) |
| **RSI bands** | `rsiInBand` / recovery cross | s03 mandate entry (dual cross) |
| **RSI slope** | `falling(rsi(close,13), 3)` | s04/s05 onPosition decay exit |
| **Fib windows** | 8, 13, 21, 34 | Entry/exit/trail periods |

## What we stole (R5 winners)

| Pattern | Source | R6 application |
|---------|--------|----------------|
| RSI>75 take-profit | agent-05 s04 | s01–s05 cascades |
| EMA8 + Donchian21 entry | agent-05 s04 | s01, s02, s04, s05 |
| MACD(13,34,8) regime exit | agent-05/06 | s05 onBar + onPosition |
| Profit lock 8/3%, 13-bar stop | agent-06 s05 | All onPosition stacks |
| EMA13/34 trail | agent-06 s05 | s02–s05 |

## Round 6 lineup

| File | Name | Entry | Exit / risk |
|------|------|-------|-------------|
| `round-06/s01.ms` | Rsi75TakeVaultR6 | EMA8 + Donchian21 | Minimal RSI75 vault + RSI<35 fail |
| `round-06/s02.ms` | DualRsi75CascadeR6 | EMA8 + Donchian21 | Dual RSI(8/13) 75/78 TP + 32/35 fail + EMA13 break |
| `round-06/s03.ms` | RsiDualRecoveryR6 | RSI(8) cross 35 + RSI(13)>35 + EMA834 | Dual RSI cascade exit (mandate entry) |
| `round-06/s04.ms` | RsiSlopeCrownR6 | EMA8 + Donchian21 | s02 cascade + `falling(rsi13,3)` + `falling(rsi8,2)` |
| `round-06/s05.ms` | RsiCrownFlagshipR6 | EMA8 + Donchian21 | Full dual-RSI + MACD + RSI slope crown |

## Self-test (3m eval only)

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-06/s05.ms --symbol SPY
python examples/strategy-tournament/agents/agent-04/round-06/eval_all.py
```

## R6 eval results (2026-04-14 → 2026-07-13)

| Strategy | Score | Mean Sharpe | vs B-H | Median MDD | WF Sharpe | Trades |
|----------|------:|------------:|-------:|-----------:|----------:|-------:|
| **s05** | **1.602** | **2.179** | **+0.794** | 0.027 | 2.250 | 161 |
| s02 | 1.532 | 2.064 | +0.679 | 0.029 | 2.285 | 155 |
| s04 | 1.532 | 2.064 | +0.679 | 0.029 | 2.285 | 155 |
| s01 | 1.200 | 1.537 | +0.153 | 0.077 | 2.414 | 105 |
| s03 | 0.137 | 0.049 | −1.336 | 0.008 | 1.683 | 36 |

**Best candidate:** `round-06/s05.ms` — **beats R5 field winner (1.549) by +0.053**. Dual RSI cascade + RSI75 + RSI<35 fail + MACD companion + `falling(rsi13,3)` onPosition.

## Key R6 lessons

1. **RSI>75 + dual-speed exits** (8@78 / 13@75 + 8@32 / 13@35 fail) is the RSI identity edge over agent-05's single-period RSI75.
2. **RSI slope onPosition** (`falling(rsi13,3)`) adds +0.070 composite over s02 when paired with MACD anchor trail — first measurable RSI-slope lift.
3. **RSI band entry gate** (s03 probe) and **restrictive dual-RSI entry gates** on s05 v1 both failed — keep entry simple (EMA8 + Don21), own RSI on exit.
4. **Mandate recovery entries** (s03) remain structurally weak on bull 3m tape without `bars_since` / HTF.
5. s04 ≡ s02 on eval — RSI slope fires but does not differentiate when full cascade already exits; slope matters in s05's layered stack.

## Expected posture

- **s05 targets tournament crown** — 1.602 exceeds agent-05 s04 (1.549).
- s02 is the pure-RSI (no MACD) reference at 1.532.
- s01 is minimal vault baseline; best WF (2.414) but weak 3m Sharpe.
- s03 defends BRIEF mandate; not competitive on this tape.
