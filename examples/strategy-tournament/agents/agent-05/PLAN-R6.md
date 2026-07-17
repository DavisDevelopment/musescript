# Agent 05 — Round 6 Plan (FINAL)

## R5 recap — crown held

**Champion:** `Ema8Rsi75Fall3R5` (round-05/s04.ms) — score **1.549**, WF **2.30**, vs BH **+0.702**

Field meta fully diffused: every agent cloned EMA8 + `cascadeExit` OR + `falling(hist,3)`. Round 6 mandate: **differentiate without breaking the crown shell**.

## R6 probe campaign (5 variants, 3m eval)

Single-axis probes on the R5 crown architecture. Fib windows (5/8/13/21/34), `&&`/`||` chains, `strategy`-first blocks.

### Key findings

| Pattern | Score | d_sh | WF | vs crown | Notes |
|---------|------:|-----:|---:|---------:|-------|
| **s01 crown anchor (RSI75 + fall3 + EMA8)** | **1.549** | **+0.702** | **2.30** | — | Identical to R5 s04 — field clone baseline |
| s03 staged Don8 early + Don13 late | **1.549** | +0.702 | 2.30 | 0.000 | Neutral — 13-low cascade fires before bars 5–7 window matters |
| s04 ATR profit lock (2×ATR8) | **1.549** | +0.702 | 2.30 | 0.000 | Neutral — calibrates to same exits as fixed 3% equity lock on this tape |
| s05 EMA5 entry + fall2 | 1.293 | +0.342 | 2.17 | −0.256 | Faster entry + faster momentum exit = premature flat on QQQ/AMD |
| s02 RSI78 vault (vs RSI75) | 1.207 | +0.279 | 1.87 | −0.342 | Confirms R5 probe — QQQ Sharpe collapses 4.50→1.68 |

**Breakthrough mechanism (unchanged):** EMA8 entry gate + RSI75 cascade + `falling(m8.hist, 3)` onPosition. No R6 axis beats it on the official window.

**Differentiation value:** s02/s05 document anti-patterns for the field; s03/s04 prove staged Donchian and ATR locks are **orthogonal** to the crown on 3m daily bars — safe to combine elsewhere without regression risk.

## Round 6 strategy ladder

| ID | Name | Entry | Exit / risk delta | Target |
|----|------|-------|-------------------|--------|
| s01 | Ema8Rsi75Fall3R6 | `close > ema(8)` + Don21 | R5 crown clone — RSI75 cascade + fall3 | **Defend** (score **1.549**) |
| s02 | Ema8Rsi78Fall3R6 | EMA8 + Don21 | RSI **78** vault probe | Anti-pattern (score **1.207**) |
| s03 | Ema8StagedDon813R6 | EMA8 + Don21 | Don8 onPosition bars 5–7; Don13 + cascade onBar | Neutral tie (score **1.549**) |
| s04 | Ema8Rsi75AtrLockR6 | EMA8 + Don21 | `close > entry + 2×ATR(8)` profit lock vs 3% | Neutral tie (score **1.549**) |
| s05 | Ema5Rsi75Fall2R6 | `close > ema(5)` + Don21 | `falling(hist,2)` bars≥5 | Swing probe (score **1.293**) |

## Architecture notes

### Staged Donchian (s03)

```muse
onBar {
  when donchianLow(13) || cascadeMomentum(13): flat()
}
onPosition {
  when bars_in_trade >= 5 && bars_in_trade < 8 && donchianLow(8): flat()
}
```

Early 8-low never fires independently — cascade momentum or 13-low exits dominate first. Needs `partial_flat` or delayed cascade to realize staged benefit.

### ATR profit lock (s04)

```muse
when bars_in_trade >= 8 && close > entry_price + 2 * atr(close, 8): flat()
```

On 3m eval, every trade that hits 3% equity lock also satisfies 2×ATR8 threshold (and vice versa).

### EMA5 + fall2 (s05)

```muse
when close > e5 && donchianHigh(21): long()
when bars_in_trade >= 5 && falling(m8.hist, 2) && m8.hist < 0: flat()
```

EMA5 admits more false breakouts; fall2 exits before QQQ/META runners mature. WF still decent (2.17) but basket Sharpe drops −0.36.

## vs field (R6 expected clones)

| Clone target | Our counter |
|--------------|-------------|
| agent-02 Ema813 + dual fall3 | Keep pure EMA8 — simpler, same score |
| agent-03 fall2 + crossunder | fall3-only wins; fall2 −0.26 score |
| agent-06 staged Donchian | Staged layer neutral on 3m — no lift |
| RSI78 “runner preservation” | Confirmed anti-pattern — hurts QQQ |

## Self-test

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/round-06/s01.ms
python examples/strategy-tournament/agents/agent-05/round-06/eval_all.py
```

## Final round verdict

**Crown defended at 1.549.** Ship s01 as official submission; s03/s04 as equivalent backups. Document s02/s05 probes so the field avoids re-discovering RSI78 and EMA5+fall2 traps.
