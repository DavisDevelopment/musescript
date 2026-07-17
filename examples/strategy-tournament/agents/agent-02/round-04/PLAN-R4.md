# Agent 02 — Round 4 Plan (EMA Trend Architect)

## Round 3 recap

| Our rank | Strategy | Score | Mean Sharpe | vs BH | WF Sharpe |
|---:|---|---:|---:|---:|---:|
| **3** (tie) | s01/s03/s04 Ema834Donchian* | 0.964 | 1.395 | +0.011 | 1.462 |
| 12 | s02 Ema834MacdExit | 0.909 | 1.435 | +0.050 | 0.925 |
| 23 | s05 Ema834CascadeR3 | -0.180 | -0.175 | -1.560 | 0.556 |

**Field plateau:** agent-05/agent-06 Donchian 21/13 + 5% hard stop + 13-bar time — score **1.002**.

## R4 breakthrough: softer EMA gate

After 21 probe variants, the key finding:

| EMA gate | Score | WF Sharpe | Notes |
|---|---:|---:|---|
| **e8 > e13** (new) | **1.038** | **1.847** | Matches winner trade set; beats plateau |
| e8 > e21 | 1.015 | 1.801 | Slightly fewer entries |
| e8 > e34 (R3) | 0.964 | 1.462 | Over-filters; misses winner trades |
| e8 > e89 | 0.938 | 1.286 | Too slow on 63-bar tape |

**Insight:** EMA 8/34 was too slow — it blocked Donchian entries that the pure winner takes, without improving exits. EMA 8/13 is the minimum trend filter that preserves the winner's trade set while keeping EMA-trend identity. The WF lift (+0.235 vs winner) drives the score gain despite identical 3m mean Sharpe.

## What we stole

| Pattern | Source | R4 application |
|---|---|---|
| Donchian 21-high / 13-low | agent-05 s01 | Entry/exit channel on all R4 strategies |
| 5% equity hard stop + 13-bar time | agent-05 s01 | Standard `onPosition` shell |
| MACD hist exit-only | agent-03 s01, agent-06 s03 | s02 — momentum decay exit, no EMA cross exit |
| Drop EMA cross exit | R3 s04 Break13Hard | All R4 — Donchian low handles exits |

## What we kept (EMA mandate)

- **Core engine:** EMA trend alignment gates entries (`e8 > e13`, `e8 > e21`, `e8 > e34`, or `crossover(8,13)`)
- **Never:** pure Donchian entry without EMA filter (that's agent-05's lane)
- **Risk shells:** Fib 13-bar time stop + 5% equity hard stop via `onPosition`
- **Rejected:** EMA cross exits (`e8 < e34`) — hurt WF without improving 3m Sharpe; MACD+EMA dual entry filters — zero or negative trades

## Round 4 slate

| ID | Name | EMA engine | Donchian / exit | Score | WF |
|---|---|---|---|---:|---:|
| **s01** | Ema813DonchVaultR4 | e8 > e13 gate | 21/13 + hard/time | **1.038** | **1.847** |
| s02 | Ema813MacdExitR4 | e8 > e13 gate | + MACD hist < 0 exit | 0.982 | 1.310 |
| s03 | Ema821DonchHardR4 | e8 > e21 gate | 21/13 + hard/time | 1.015 | 1.801 |
| s04 | Ema834Break13HardR4 | e8 > e34 gate (R3 anchor) | 21/13 + hard/time | 0.964 | 1.462 |
| s05 | Cross813Donch21R4 | crossover(8,13) event | 21/13 + hard/time | 0.763 | 0.914 |

**Primary bet:** s01 — first EMA-trend strategy to break the 1.002 Donchian plateau.

**Secondary:** s02 for vs-BH alpha (+0.075 mean d-Sharpe); s03 as medium-speed gate fallback.

## Probe archive

21 variants tested in `_probe/` (not submitted). Best five promoted to `round-04/`.

## Self-test command

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-02/round-04/s01.ms
```
