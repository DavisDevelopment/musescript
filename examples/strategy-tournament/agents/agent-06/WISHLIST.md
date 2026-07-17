# Agent 06 — MuseScript / Runtime Wishlist

Language and runtime features that would unlock cleaner maximalist strategies and reduce workarounds observed across R1–R7.

## Template system

1. ~~**Working stmt-template invocation**~~ — **SHIPPED R7.** `TrailingStop(0.08)`, `TimeExit(21)`, `StagedProfitLock()` expand via gene-runner. Used live in s01–s05.

2. **Template composition / mixin syntax** — ability to `use TrailingStop(0.08), TimeExit(21), ProfitLock(8, 0.05)` in strategy scope instead of listing each stmt call separately.

3. **Reserved-name lint** — `momentumExit` collided with a built-in expecting 1 arg (s04 compile failure). Compiler should warn on shadowing stdlib template names.

4. **Parameterized exit templates with `onBar` + `onPosition`** — single template that can emit both bar-level and position-level rules (e.g. staged Donchian 8-low then 13-low).

## Risk / position management

5. **Native trailing stop** — `trail_stop(atr(13) * 2)` or `trail_below(ema(close, 13))` instead of manual `close < ema` each bar in onPosition.

6. **Pyramiding / scale-in** — `long(qty)` or `add()` when already long and a second entry signal fires (dual-path entries in s05 would be cleaner).

7. **Partial exits** — `flat(0.5)` to take half at RSI overbought and let remainder ride the Donchian trail.

8. **Entry price / high-water mark builtins** — `max_favorable_excursion`, `entry_price`, `bars_since_peak` for profit-lock templates without reinventing via unrealized_pnl proxies.

## Multi-symbol / portfolio

9. **Multi-symbol strategies** — reference `SPY.close` as regime filter while trading `NVDA` (would help single-name laggards without abandoning Donchian core).

10. **Cross-symbol templates** — `relative_strength(sym, benchmark, 21)` for NVDA/META specialization without separate strategy files per agent-05 probe ladder.

## Indicators / operators

11. **`&&` / `||` short-circuit in when-clauses** — already work; wish: compile-time dead-branch elimination when a template arg is constant.

12. **Fib window type alias** — `Window` already enforced; wish for `Fib = 1|2|3|5|8|13|21|34|55|89` literal type so `donchianHigh(22)` fails at compile time.

13. **Squeeze / ATR expansion builtins** — `atr(5) > atr(13)` and `bb_width(13) < threshold` as first-class templates (agent-05 BRIEF patterns required verbose manual code).

14. **Chandelier / ATR trail builtin** — R5 hand-rolls `close < highest(high, 8) - 2 * atr(close, 8)` in every ATR layer; `chandelier_exit(8, 2)` would collapse 3 lines per strategy.

15. **Dual-indicator template refs** — `dualMacdBear(fast, slow)` cannot reference pre-bound `slow.hist` from strategy scope; forces duplicate MACD calls or strategy-local vars (s04/s05 workaround).

16. **Staged profit-lock mixin** — R5 copies two-tier `5@2% / 8@3%` blocks across s03/s05; parameterized `StagedProfitLock([5,0.02],[8,0.03])` needs working stmt invocation.

## Developer experience

17. ~~**`--eval` score mode in tournament_lab**~~ — **SHIPPED R7** as `crypto_fx_lab.py --eval` returning composite `score` + `wf_mean_sharpe`.

18. **Strategy diff / template extract** — show which template expansions differ between s02 and s05 (identical 3m scores until WF/other windows diverge).

19. **Bar-level debug trace** — `--trace SPY 2026-05-01` listing which `when` clause fired; critical for proving EMA8 vs EMA13 cascade fired on META (+0.097 d-Sharpe in R5).

20. **Layer no-op detector** — flag onPosition `when` clauses that never fire across eval basket (R5 dual MACD / ATR / staged profit all no-op on 3m with EMA8 engine).

## R6 cycle-close observations

21. **Entry vs exit EMA disambiguation** — R5 used `belowEma(8)` thinking "EMA8 trail"; agent-05 crown uses EMA8 for **entry** (`close > e8`) and EMA13 for **cascade exit**. Compiler hint on template param names (`fastEma` in `cascadeExit`) would prevent 0.109 score regression.

22. **Converged meta detector** — R6 s01–s05 all score **1.549** identically; 10 onPosition layers in s05 are no-op when core rail matches agent-05. Runtime should report "redundant clause" when a `when` never fires before an earlier clause in the same block.

23. **Dual RSI position-scope** — `rsi(8) > 78` onPosition (s03/s05) never differentiated from s01 on 3m bull tape; position-scoped fast RSI may only fire in extended runners (QQQ +4.5 Sharpe). Per-symbol layer fire counts needed.

24. **Asymmetric Donchian staged exit** — `donchianLow(8)` at bars≥8 (s05 layer 8) is subsumed by onBar `donchianLow(13)` and EMA13 trail on 3m; fires only when price bleeds without hitting wider channel. `bars_since` would let us arm 8-low only after profit-lock tier 1.

## R7 crypto+FX cycle observations

25. **Asset-class entry profiles** — single strategy cannot trade EUR (EMA cross fires 2×) and BTC (Don8 fires 10×) optimally. Need `asset == "forex"` gate or volatility-normalized Donchian length without per-symbol files.

26. **Next-open gap model** — daily crypto gaps invalidate same-close equity params; 8% stop and Don8 entry are hand-tuned compensations. Builtin `gap_at_open()` or fill-slippage estimate would calibrate stops.

27. **`falling(x, n, minBars)` shipped** — used in s02–s05; eliminates one `bars_in_trade >= k &&` per clause. Wish: same for `rising` inside expr templates referencing bound MACD vars.

28. **FX zero-trade scoring artifact** — EURUSD 0 trades yields +3.26 d-Sharpe vs drifting BH; composite score rewards non-participation. Per-asset minimum-trade floor or participation penalty would force FX-capable entries.

29. **Crypto WF inversion** — walkforward mean Sharpe −1.32 while 3m d-Sharpe +0.80; 2019/2022/2024 crypto windows unlike eval window. Need WF windows aligned to halving cycles or vol regimes.

30. **Volume confirmation (crypto tapes)** — volume series exists on Binance daily OHLC; `relative_volume(n)` would filter false Don8 breaks on thin bars (agent-05 BRIEF pattern).

## Priority ranking

| Priority | Wish | R7 pain it solves |
|---:|---|---|
| P0 | Layer no-op / redundancy detector | s03–s05 identical to s02 on crypto 3m |
| P0 | Asset-class entry profiles | EUR 0 trades / FX under-participation |
| P0 | Entry vs exit EMA lint | Prevent belowEma(8) vs belowEma(13) confusion |
| P1 | Template composition mixin | 8 stmt calls in s05 still verbose |
| P1 | Chandelier / ATR trail builtin | ATR layer boilerplate in s04/s05 |
| P1 | Volume confirmation helper | False Don8 on thin crypto bars |
| P2 | Dual-indicator template refs | dualMacdBear without duplicate MACD() |
| P2 | Next-open gap / slippage model | Stop calibration across domains |
| P3 | Partial exits | RSI72 take-profit without full flat |
