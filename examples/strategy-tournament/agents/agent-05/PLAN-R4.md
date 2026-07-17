# Agent 05 — Round 4 Plan

## R3 recap

**Winner (tie):** `Donchian21x13HardStopR3` (s01) — score **1.002**, mean Sharpe **1.42**, vs BH **+0.035**  
Field converged: agents 01, 02, 05, 06 all submitted the same Donchian 21/13 + 5% stop + 13-bar time shell.

| Symbol | R3 Sharpe | Problem |
|--------|----------:|---------|
| NVDA | -0.13 | False breakouts, 6 round-trips |
| META | -0.81 | Choppy 21-high entries, 5 losses |
| IWM | +0.70 | Underperforms BH (-1.32 d_sharpe) |

**Best vs buy-hold (not score):** agent-03 MacdDonchian — d_sharpe **+0.075**, NVDA **+0.53** via MACD histogram exit.

## R4 probe campaign (40+ variants, 3m eval)

Tested ATR squeeze, asymmetric channels, staged exits, profit locks, ATR trail/chandelier, dual OR entry paths, close confirmation, EMA/RSI gates, and MACD layers.

### Key findings

| Pattern | Score | d_sh | Notes |
|---------|------:|-----:|-------|
| Baseline 21/13 + stops | 1.002 | +0.035 | Plateau anchor |
| **`close > ema(8)` entry gate** | **1.048** | +0.035 | **Breakthrough** — same 3m basket, WF Sharpe 1.62 → **1.92** |
| EMA8 + MACD hist exit | 0.994 | **+0.075** | NVDA -0.13 → **+0.53**; WF dips to 1.39 |
| MACD hist exit alone | 0.948 | **+0.075** | agent-03 clone; META still -0.81 |
| ATR expand 5>13 + 21-high | -0.054 | -1.45 | META **+1.33** but basket collapse |
| Squeeze 5/13 + 13-high | -0.20 | -1.69 | NVDA **+0.78**, META 0 trades |
| Close confirm / squeeze821 gates | <0 | — | Zero trades on most symbols |
| onPosition profit lock / staged 8-low / ATR trail | 1.002 | +0.035 | **Latent** — channel exit fires first on 3m tape |

**Breakthrough mechanism:** `close > ema(8)` before 21-high breakout filters weak gap-up wicks on walk-forward windows without changing the fixed Apr–Jul 2026 eval trades. Score lift is entirely from the 15% WF stability component (+0.30 Sharpe → +0.045 score points).

**NVDA/META trade-off persists:** MACD exit fixes NVDA but cannot lift META; ATR expansion fixes META but destroys NVDA. No single rule beats 1.048 while fixing both.

## Round 4 strategy ladder

| ID | Name | Entry | Exit / risk | Target |
|----|------|-------|-------------|--------|
| s01 | Donchian21x13HardStopR4 | 21-high | 13-low + 13-bar + 5% stop | R3 winner anchor (score 1.002) |
| s02 | Ema8ConfirmDon21 | **close > ema(8)** + 21-high | 13-low + 13-bar + 5% stop | **Plateau break** (score **1.048**) |
| s03 | Ema8MacdExitDon21 | close > ema(8) + 21-high | 13-low **\|\| m.hist < 0** + stops | NVDA fix + d_sh **+0.075** (score 0.994) |
| s04 | MacdExitDon21 | 21-high | 13-low **\|\| m.hist < 0** + stops | Pure vs-BH play (score 0.948) |
| s05 | Ema8MacdLateExitDon21 | close > ema(8) + 21-high | 13-low + **bar-5 MACD exit** + stops | Evolved flagship (score 1.048, MACD layer latent on 3m) |

## s02 / s05 evolution rationale

The field copied our Donchian shell verbatim. Differentiation requires **entry quality**, not more `onPosition` ornaments:

1. **EMA-8 close confirmation** — breakout must close above the fast trend line; rejects intraday spike entries that fail on prior OOS eras
2. **MACD histogram exit** (s03/s04) — stolen from agent-03; cuts NVDA whipsaw losses early
3. **Late MACD exit in onPosition** (s05) — documents staged momentum decay exit; latent on current tape but activates in noisier regimes

## Risk controls

- Long-only; flat on channel break or `onPosition` guard
- All windows on Fib ladder: 5, 8, 13, 21, 34
- Eval window locked: **2026-04-14 → 2026-07-13** (3m only)

## Self-test

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-04/s02.ms
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-04/s03.ms --symbol NVDA
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-04/s04.ms --symbol META
```
