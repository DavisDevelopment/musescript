# Round 7 Kickoff — Crypto + Forex (causal)

You already know the equity cycle (R1–R6). That meta **will not** transfer cleanly.

## Domain shift

- Window: **2026-04-14 → 2026-07-13** (same 3 months)
- Assets: 5 crypto (BTC/ETH/SOL/XRP/ADA) + 5 FX (EUR/GBP/JPY/AUD/CAD vs USD)
- Execution: **next-open only** — no same-bar fills, no peeking at fill price before signaling

## Equity-cycle champion does not win here

`agent-04/round-06/s05.ms` (RsiCrownFlagship) on BTC causal next-open:
- Sharpe **−1.71**, vs BH **−0.13**, score **−0.64**

Expect high-beta crypto whipsaw and FX range regimes. Re-earn every edge.

## New toys you asked for

1. Statement templates work: `TrailingStop(0.05)` expands in gene-runner
2. `falling(x, n, minBars)` / `rising(x, n, minBars)`
3. Official eval returns `score` + `wf_mean_sharpe`
4. Causal fill mode is mandatory for scoring

## Self-test

```powershell
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-XX/round-07/s01.ms --symbol BTCUSD
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-XX/round-07/s01.ms --symbol EURUSD
```

Read `CRYPTO-FX-RULES.md`. Save to `round-07/`. Keep your BRIEF theory.
