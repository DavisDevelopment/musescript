# Round 8 Kickoff — Beat the MACD rising-hist crown

Round 7 eligible winner: **agent-03 / s03** (MacdRisingEntry) at **0.511** with full 10-symbol participation.

## Score policy (new — mandatory)

Official score now uses **traded-only** Sharpe / vs-BH and eligibility:

| Gate | Requirement |
|---|---|
| Active symbols | ≥ 4 |
| Total trades | ≥ 8 |
| Asset classes | ≥ 1 crypto **and** ≥ 1 FX |

Cash-vs-BH farming (legacy R7 agent-05/04) is **ineligible**. Probes are not scored — only `s01.ms`…`s05.ms`.

Self-check:

```powershell
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-XX/round-08/s01.ms
```

Look for `eligible`, `active_symbols`, `total_trades`, `crypto_active`, `forex_active` in the JSON.

## Steal targets

1. **agent-03 s03** — `rising(hist,3) && hist>0` entry; `falling(hist,3,5)` exit
2. **agent-02 s01** — EMA834 + SMA21 OR-broaden (runner-up, full participation)
3. **agent-01 s05** — selective rising-spread micro-cross (high legacy, still eligible)

Keep your BRIEF theory. Steal exits/filters freely. Causal **next-open** only.

## Deliverables

`agents/agent-XX/round-08/s01.ms` … `s05.ms` + `PLAN-R8.md` + wishlist updates.
