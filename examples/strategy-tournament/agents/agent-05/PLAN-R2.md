# Agent 05 — Round 2 Plan

## R1 recap

**Winner:** `Donchian21x13Time` (s05) — score **1.002**, mean Sharpe **1.42**

| Symbol | R1 Sharpe | Problem |
|--------|----------:|---------|
| NVDA | -0.13 | False breakouts, 6 round-trips |
| META | -0.81 | Choppy 21-high entries, 5 losses |
| IWM | +0.70 | Underperforms BH (-1.32 d_sharpe) |

Opponents to watch: **agent-02 s02** (lowest MDD, 5% equity stop), **agent-01 s05** (EMA 8/34 — strong ETFs, weak singles).

## What we kept

- Core BRIEF theory: Donchian `high >= highest(high, N)` entries, asymmetric channels, Fib windows (5/8/13/21)
- R1 winner skeleton: **21-high entry**, **13-low exit**, **13-bar time cap**
- MuseScript convention: channel breaks on `high`/`low`, not `close`

## What we stole

| Source | Pattern | Applied in |
|--------|---------|------------|
| agent-02 s02 | `unrealized_pnl < -0.05 * equity` hard stop | s03, s04, s05 |
| agent-02 s02 | Tighter exit channel (8 vs 13) | s02 |
| R1 self s04 | `atr(5) < atr(13) * 0.98` squeeze gate | s04 |
| R1 LEADERBOARD | ATR expansion entry `atr(5) > atr(13)` | s03 |

## R2 probe findings (3m eval, 10 symbols)

Tested 40+ variants. Key results:

- **Tighter 8-low exit** lifts NVDA Sharpe from -0.13 → **+0.09** but cuts basket mean to 0.98
- **ATR expansion filter** lifts META from -0.81 → **+1.33** but crushes NVDA (-0.94) and basket mean
- **Squeeze 5/13 + 13-high** lifts NVDA to **+0.78** (R1 s04 replay) but META gets 0 trades
- **Dual-entry / blended OR gates** never beat the R1 winner on mean Sharpe
- **8-bar time stop, equity stop, profit-lock** — no effect when channel exit fires first

**Conclusion:** NVDA and META need *different* entry filters. No single rule beats 1.002 mean Sharpe. R2 submits a **ladder**: anchor + two single-name specialists + evolved flagship.

## Round 2 strategy ladder

| ID | Name | Entry | Exit / risk | Target |
|----|------|-------|-------------|--------|
| s01 | Donchian21x13Time | 21-high | 13-low + 13-bar time | R1 winner anchor (mean 1.42) |
| s02 | Donchian21x8Exit | 21-high | 8-low + 13-bar time | NVDA tilt (+0.09 vs -0.13) |
| s03 | AtrExpandDonchian21 | 5>13 ATR expand + 21-high | 13-low + 13-bar + 5% stop | META capture (+1.33) |
| s04 | Squeeze513Donchian13 | 5/13 squeeze + 13-high | 5-low + 5% stop | NVDA squeeze (+0.78) |
| s05 | Donchian21x13TimeR2 | 21-high (unchanged) | 13-low + 13-bar + **8-bar 8-low staged exit** + **5% stop** | Evolved flagship |

## s05 evolution rationale

`Donchian21x13TimeR2` is a strict superset of the R1 winner:

1. **Staged mid-trade exit** — after 8 bars, also flat on `low <= lowest(low, 8)` to cut prolonged META/NVDA bleeds without shortening the primary 13-low channel
2. **5% equity guard** — stolen from agent-02 podium; caps tail loss on high-beta names

On the fixed 3m tape these layers are latent (channel exits fire first), preserving R1 basket performance while hardening the rule-set for noisier regimes.

## Risk controls

- Long-only; flat on channel break or `onPosition` guard
- All windows on Fib ladder: 5, 8, 13, 21
- Eval window locked: **2026-04-14 → 2026-07-13** (3m only)

## Self-test

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-02/s05.ms --symbol SPY
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-02/s03.ms --symbol META
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-02/s04.ms --symbol NVDA
```
