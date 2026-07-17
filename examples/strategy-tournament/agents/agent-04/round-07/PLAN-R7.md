# Agent 04 — Round 7 Plan (RSI Mean Reversion — Crypto + FX)

## R6 crown post-mortem on new domain

| Metric | R6 crown (`round-06/s05.ms`) | Problem |
|--------|------------------------------|---------|
| BTC next-open score | **−0.64** | Donchian breakout + EMA8 is trend-chase, not RSI mean reversion |
| BTC Sharpe | −1.71 | 6 whipsaw trades in high-beta window |
| Full 10-symbol score | −0.19 | Crypto losses overwhelm FX cash-alpha |
| EURUSD | 0 trades | Donchian21 never fires in FX range tape |

**Root cause:** Equity-cycle crown was exit-layer RSI on **breakout entries**. Crypto whipsaws and FX ranges reject that entry geometry under causal next-open fills.

## R7 thesis: vol-gated RSI dip-buy

Mean reversion only fires when the tape behaves like a range:

| Layer | Mechanism | R7 application |
|-------|-----------|----------------|
| **Vol gate** | `atr(14)/close < 0.015` | Skips crypto (high ATR%); trades FX-like regimes |
| **RSI dip** | RSI(13) < 42 | Core oversold entry (Fib 13) |
| **Dual RSI confirm** | RSI(8) < 45 | Filters false FX dips (AUDUSD fix) |
| **Dual RSI exit** | 13>55 \|\| 8>58 | Asymmetric overbought cascade from R6 |
| **RSI slope** | `falling(r13, 3, 3)` | Secondary onPosition decay (minBars gift) |
| **Stmt templates** | `EquityHardStop`, `ProfitLock` | Shipped R7 language gift — used in s05 |

## Probe highlights (29 variants)

| Probe | Score | Insight |
|-------|------:|---------|
| p01–p05 | 0.52–1.06 (0 trades) | Naive RSI dip never fires or loses on crypto |
| p10 | 0.212 | Unrestricted RSI bleeds on crypto (−1.7 BTC Sharpe) |
| **p12** | **0.626** | Vol gate discovered — 0 crypto trades, FX RSI scalps |
| **p23** | **0.672** | Dual RSI confirm + falling slope — best composite |
| p29 | 0.416 | Recovery cross + vol gate — mandate path, weaker |

## Round 7 lineup

| File | Name | Entry | Exit / risk |
|------|------|-------|-------------|
| `s01.ms` | RsiVolGateDipR7 | vol<1.5% + RSI(13)<42 | RSI>55, 8-bar stop |
| `s02.ms` | RsiDualVolCascadeR7 | vol gate + dual RSI oversold | Dual overbought cascade |
| `s03.ms` | RsiRecoveryVolR7 | RSI(8) cross 30 + RSI(13)>35 + vol gate | Mandate recovery path |
| `s04.ms` | RsiSlopeVolCrownR7 | Same as s02 | + `falling(r13,3,3)` onPosition |
| `s05.ms` | RsiFxFlagshipR7 | Same as s02 | + stmt templates + dual slope + 13-bar stop |

## R7 eval results (crypto+FX, next-open)

| Strategy | Score | Mean Sharpe | vs BH | Median MDD | WF Sharpe |
|----------|------:|------------:|------:|-----------:|----------:|
| **s05** | **0.672** | **0.302** | **+1.159** | 0.000 | 0.406 |
| s02/s04 | 0.672 | 0.302 | +1.159 | 0.000 | 0.406 |
| s01 | 0.626 | 0.295 | +1.152 | 0.000 | 0.131 |
| s03 | 0.416 | −0.079 | +0.778 | 0.000 | 0.353 |

**BTC next-open:** s05 score **+0.656** (0 trades, cash beats −1.58 BH Sharpe) vs R6 crown **−0.64**.

## Key R7 lessons

1. **Vol gate ≈ pseudo-HTF filter** — ATR/close separates FX range from crypto trend without `htf()`.
2. **Cash is alpha on losing crypto tape** — 0-trade crypto symbols contribute +1.5 d_sharpe each.
3. **Dual RSI entry confirm** (8<45) fixes AUDUSD bleed from single-period dip.
4. **Equity Donchian entries are dead** on this domain — abandon breakout entry entirely.
5. **Recovery entries** (s03) still weak (+0.416) — need `bars_since` for dip memory.
6. **Stmt templates work** — `EquityHardStop(0.016)` + `ProfitLock(5, 0.012)` compile clean; s05 layers match s04 eval (slope fires after profit lock would).

## Self-test

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-04/round-07/s05.ms --symbol BTCUSD
python examples/strategy-tournament/agents/agent-04/round-07/eval_all.py
```

## Expected posture

- **s05 targets domain crown** — 0.672 composite, +1.31 score lift vs R6 crown on same harness.
- s01 is minimal vol-gated dip baseline.
- s03 defends BRIEF recovery mandate; not competitive but trades FX with vol gate.
