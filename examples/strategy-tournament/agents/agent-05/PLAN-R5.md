# Agent 05 — Round 5 Plan

## R4 recap — dethroned

**Our best:** `Ema8ConfirmDon21` (s02) — score **1.048**, WF Sharpe **1.92**  
**Winner:** agent-06 `CascadeCrownR4` (s05) — score **1.427**, vs BH **+0.593**

Agent-06 copied our Donchian 21/13 shell but **stripped the EMA8 entry gate** and won entirely on **exit-only cascade layers** (MACD bear + RSI vault + EMA trail + onPosition profit lock). Agent-03's `falling(macd.hist, 3)` added another +0.27 score lift on exits alone.

**Diagnosis:** We had the right entry filter (EMA8) but the wrong exit architecture. R4 onPosition ornaments were latent because 13-low fired first; agent-06 moved momentum exits to `onBar` cascade OR chains.

## R5 probe campaign (16 variants, 3m eval)

Combined our EMA8 entry edge with stolen cascade + fall3 exits.

### Key findings

| Pattern | Score | d_sh | WF | Notes |
|---------|------:|-----:|---:|-------|
| R4 anchor EMA8 + 13-low only | 1.048 | +0.035 | 1.92 | Baseline |
| EMA8 + agent-06 cascade (no fall) | 1.408 | +0.593 | 1.83 | Cascade steal works; WF dips vs pure EMA8 |
| EMA8 + cascade + `falling(hist,3)` | 1.519 | +0.699 | 2.12 | agent-03 steal; IWM flips positive |
| **EMA8 + RSI75 cascade + fall3** | **1.549** | **+0.702** | **2.30** | **Crown candidate — beats agent-06 +0.12** |
| Above + `crossunder` backup | 1.527 | +0.678 | 2.26 | Cross adds WF noise; fall3 alone wins |
| RSI vault 72 vs 75 | 1.519 vs 1.549 | — | — | Softer 75 vault preserves runners, lifts WF |
| `falling` on `onBar` vs `onPosition` | 1.436 vs 1.519 | — | — | Position-scoped fall avoids premature flat |

**Breakthrough mechanism:** EMA8 entry filters false breakouts (WF stability) while cascade + fall3 exits capture agent-06's vs-BH alpha. RSI75 (not 72) is the sweet spot — tight enough to bank gains, loose enough to keep META/QQQ runners.

**META fixed:** cascade alone → Sharpe **+1.68**; + fall3/RSI75 → **+1.08** (still positive, 3 trades vs 5 losses at R4).

## Round 5 strategy ladder

| ID | Name | Entry | Exit / risk | Target |
|----|------|-------|-------------|--------|
| s01 | Ema8ConfirmDon21R5 | `close > ema(8)` + 21-high | 13-low + 13-bar + 5% stop | R4 anchor (score **1.048**) |
| s02 | Ema8CascadeR5 | EMA8 + 21-high | agent-06 cascade OR + onPosition layers | Cascade steal (score **1.408**) |
| s03 | Ema8CascadeFall3R5 | EMA8 + 21-high | cascade + `falling(m8.hist,3)` | agent-03 steal (score **1.519**) |
| s04 | Ema8Rsi75Fall3R5 | EMA8 + 21-high | RSI75 cascade + fall3 | **Crown** (score **1.549**) |
| s05 | DonchianCrownR5 | EMA8 + 21-high | RSI75 cascade + fall3 + crossunder | Dual-momentum exit flagship (score **1.527**) |

## Architecture — `cascadeExit` template

```muse
template cascadeExit(fastEma: Window) -> Bool {
  donchianLow(13) || macdBear(13, 34, 8) || rsiOverbought(13, 75) || belowEma(fastEma)
}
```

Entry stays **Donchian-native** (`close > ema(8) && high >= highest(high, 21)`). Exits never touch entry — exit-only filters per R4 public learnings.

onPosition stack (Fib windows 5/8/13/21/34):
- 5% equity hard stop
- 13-bar time exit
- 8-bar 3% profit lock
- 5-bar EMA13 trail
- 8-bar EMA34 + MACD134 bear
- `falling(macd(8,21,5).hist, 3)` — agent-03 momentum decay

## vs agent-06 CascadeCrownR4

| Metric | agent-06 s05 | agent-05 s04 |
|--------|-------------:|-------------:|
| Score | 1.427 | **1.549** |
| Mean Sharpe | 1.98 | **2.09** |
| vs BH | +0.593 | **+0.702** |
| MDD | 3.4% | **2.9%** |
| WF Sharpe | 1.96 | **2.30** |

Delta: EMA8 entry gate + RSI75 vault + fall3-only (no redundant crossunder).

## Self-test

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-05/s04.ms
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-05/s04.ms --symbol META
python examples/strategy-tournament/agents/agent-05/round-05/eval_all.py
```
