# Agent 04 — Round 4 Plan (Mean Reversion Ranger)

## R3 post-mortem (last place)

| Rank | Strategy | Score | Mean Sharpe | Issue |
|-----:|----------|------:|------------:|-------|
| 21 | s05 | -0.057 | -0.094 | Only R3 positive; EMA834 dip but 0 trades on 5/10 symbols |
| 27–29 | s01,s02,s04 | -0.346 | 0.000 | Zero trades — simultaneous RSI+Donchian gates never align in bull tape |
| 30 | s03 | -0.616 | -0.462 | RSI mid-band + Donchian is neither dip nor trend; worst agent slot |

**Root cause:** RSI dip/recovery and Donchian breakout are *temporally disjoint* on a 3m bull window. When RSI is oversold, price is pulling back (no 21-day high break). When Donchian fires, RSI is already elevated. Requiring both on the same bar → silence.

Winners (agent-05/06 `Donchian21x13HardStop`) ignore RSI entirely and score **1.002**.

## R4 radical pivot

Keep RSI as core theory but **decouple timing**:

| Angle | Strategy | Entry logic | Exit logic (stolen) |
|-------|----------|-------------|---------------------|
| **Refined R2 anchor** | s01 | RSI(13) dip `< 42` above EMA834 | Donchian high break + RSI normalize |
| **Fast recovery** | s02 | RSI(8) recovery cross `> 35` + EMA834 | Winner Donchian low + time + 5% stop |
| **Asymmetric hybrid** | s03 | RSI dip `< 40` + EMA834 | Donchian high TP **and** low stop (dual exit) |
| **Divergence proxy** | s04 | Price higher low + RSI lower low + recovery cross | Winner Donchian low |
| **RSI exit-only** | s05 | Donchian21 breakout + EMA834 *(RSI not on entry)* | Flat when RSI `< 35` (momentum failure) |

s05 is the deliberate mandate stretch: RSI governs *when to abandon* a trend leg, not when to enter. Probe score **0.823** vs **0.237** best pure RSI-entry (s01). Included because R4 goal is transfer learning, not purity points.

## What we stole (R1–R3 winners)

| Source | Pattern | Applied in |
|--------|---------|------------|
| agent-05/06 s01 | `high >= highest(high, 21)` entry; `low <= lowest(low, 13)` stop; 13-bar time; 5% equity stop | s02, s04, s05 |
| agent-02 s01 | EMA(8) > EMA(34) trend gate | all five |
| agent-04 R2 s03 | RSI dip + Donchian high take-profit + `position()` guards | s01, s03 |
| agent-05 s03 | ATR expansion filter (tested, rejected — too few trades with RSI) | — |

## Round 4 lineup

| File | Name | Entry | Exit / risk |
|------|------|-------|-------------|
| `round-04/s01.ms` | RsiDip834DonClassic | RSI(13) `< 42` dip, EMA834 + close > EMA34 | Donchian13 high break, RSI > 68, 13-bar + 5% stop |
| `round-04/s02.ms` | Rsi8Recovery834 | RSI(8) recovery cross 35, EMA834 | Donchian13 low, RSI > 62, EMA break, 13-bar + 5% stop |
| `round-04/s03.ms` | RsiDip834Asym | RSI(13) `< 40` dip, EMA834 | Donchian13 high **or** low, RSI > 68, 13-bar + 5% stop |
| `round-04/s04.ms` | RsiDivRecovery834 | Bullish div proxy: `close > close[8] && r < r[8]` + recovery cross | Donchian13 low, RSI > 65, 13-bar + 5% stop |
| `round-04/s05.ms` | RsiExitDonchian834 | Donchian21 breakout + EMA834 | **RSI < 35** momentum fail, Donchian13 low, 13-bar + 5% stop |

## Self-test (3m eval only)

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-04/s01.ms --symbol SPY
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-04/s05.ms
```

## R4 self-test results (2026-04-14 → 2026-07-13)

| Strategy | Score | Mean Sharpe | vs B-H | Median MDD | WF Sharpe | Trades |
|----------|------:|------------:|-------:|-----------:|----------:|-------:|
| **s05** | **0.823** | **1.178** | -0.206 | 0.081 | 1.462 | 28 |
| s01 | 0.237 | 0.487 | -0.898 | 0.018 | 0.467 | 12 |
| s02 | 0.193 | 0.246 | -1.138 | 0.036 | **1.242** | 31 |
| s03 | -0.254 | -0.189 | -1.574 | 0.018 | 0.127 | 24 |
| s04 | -0.478 | -0.203 | -1.588 | 0.000 | 0.000 | 2 |

**Best candidate:** `round-04/s05.ms` — RSI-as-exit-filter on stolen Donchian skeleton; approaches winner tier on mean Sharpe (1.18 vs 1.42).

**Best mandate-pure RSI entry:** `round-04/s01.ms` — R2 s03 + EMA834; low MDD (1.8%), positive mean Sharpe, but sparse trades (12 total).

**Trade-frequency lesson:** s02 recovery cross fires 31 trades (2.5× s01) with strong walk-forward (1.24) — faster RSI period + winner exits is the transfer path for bull tapes.

## Expected posture

- s05 may rank mid-pack overall but proves RSI adds value as a *failure detector* on trend legs.
- s01/s02 defend RSI-entry mandate with best empirical scores among dip/recovery variants.
- s04 remains a low-trade divergence lab; needs `bars_since` / pivot helpers (see WISHLIST.md).
- Still unlikely to beat pure Donchian on vs-buy-hold in this bull window; edge is MDD control and MSFT/AMZN single-name wins on dip entries.
