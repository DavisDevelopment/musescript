# Round 8 — Crypto + FX Results (local recovery)

Eval: **2026-04-14 → 2026-07-13** · execution: **next-open** · eligibility gates active

## Winner

**agent-02 / s03.ms** — A02S03_Ema1345SlowR8  
Score **0.782** | legacy **0.788** | traded Sharpe **0.625** | vs BH* **+1.214** | **9** active symbols · **30** trades · WF **0.074**

Formula: EMA 13/45 trend with SMA34 gate, plus MACD 8/21/5 rising-hist participation.

`
when (fast > slow || rising(m.hist, 3)) && close > gate: long()
when crossunder(fast, slow) || close < gate || falling(m.hist, 3, 5): flat()
`

## Why this matters

Round 8 was recovered locally after all six subagents failed on API limits. The local slate still produced a real regime jump: R7 crown **0.511 → 0.782**. Unlike the discarded R7 cash traps, the winner passes activity gates and trades both asset classes.

## Podium

| # | Agent | Strat | Score | Legacy | Active | Trades | Thesis |
|---:|---|---|---:|---:|---:|---:|---|
| 1 | agent-02 | s03 | **0.782** | 0.788 | 9 | 30 | EMA13/45 + SMA34 + rising MACD hist |
| 2 | agent-05 | s01 | 0.689 | 0.655 | 10 | 52 | Don8 breakout + MACD hist filter |
| 3 | agent-04 | s04 | 0.664 | 0.630 | 10 | 74 | Broad RSI + momentum participation |
| 4 | agent-06 | s04 | 0.612 | 0.573 | 10 | 76 | Template breakout/trend hybrid |
| 5 | agent-05 | s03 | 0.586 | 0.543 | 10 | 64 | ATR squeeze softened by hist |
| 6 | agent-03 | s03 | 0.521 | 0.481 | 10 | 55 | R7 crown with trend gate |

## Lessons

- EMA trend retook the crown once MACD rising-hist was used as participation glue rather than pure entry dogma.
- Donchian/ATR can be made eligible by shortening channels (donHigh(8)) and allowing histogram participation.
- RSI recovered from R7 ineligibility by broadening the dip condition; its best R8 row is now third.
- The R7 pure MACD crown still works, but it is now the baseline, not the frontier.

## Deliverables

- Recovered Round 8 slates: gents/agent-01..06/round-08/s01.ms … s05.ms
- Official leaderboard: 
esults/round-08/LEADERBOARD-CRYPTO-FX.md
- Canvas: strategy-tournament-round-08.canvas.tsx
