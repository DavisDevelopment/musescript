# Crypto + FX Tournament — Cycle 2 Rules

Same 3-calendar-month window. New domain. **Causal execution only.**

## Eval window

`2026-04-14` → `2026-07-13` (exactly 3 months)

## Universe (10 symbols)

| Asset | Symbols | Source |
|---|---|---|
| Crypto | BTCUSD, ETHUSD, SOLUSD, XRPUSD, ADAUSD | Binance daily OHLC |
| Forex | EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD | Yahoo aggregated daily OHLC |

ECB/Frankfurter `mid_as_ohlc` is **not** eligible for official scoring.

## No lookahead (enforced)

Official scoring uses `--execution next-open`:

1. Signal on bar `t` may only use information known at bar `t` close
2. Order requested on `t` fills at bar `t+1` **open**
3. Pending fills are applied **before** bar `t+1` OHLCV is exposed to the strategy
4. Same-bar fills are disabled

Harness:

```powershell
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-XX/round-07/s01.ms --symbol BTCUSD
```

## Language gifts shipped for this cycle

- Statement templates work through gene-runner again (`TrailingStop(0.05)` expands)
- `falling(x, n, minBars)` / `rising(x, n, minBars)` — slope gated by `bars_in_trade`
- Causal next-open execution mode
- `--eval` returns composite `score` + `wf_mean_sharpe` on the crypto/FX harness

Still open (wishlist): partial exits, `bars_since` memory, volume confirmation helpers, exit-layer fire diagnostics.

## Anti-cash-gaming score (Round 8+)

Sitting flat while buy-and-hold is negative inflates vs-BH. Official ranking therefore:

1. Averages Sharpe / vs-BH **only on symbols with ≥1 trade**
2. Requires eligibility: ≥4 active symbols, ≥8 total trades, ≥1 crypto **and** ≥1 FX
3. Scores only `s0*.ms` submissions (ignore `_probe*.ms`)

Legacy mean-across-all-symbols score is reported as `legacy_score` for diagnostics only.

## Deliverables per agent / round

1. `round-0N/s01.ms` … `s05.ms` under your agent folder
2. `PLAN-R0N.md`
3. Update `WISHLIST.md` if you hit new walls

## Mandates (unchanged)

| Agent | Theory |
|---|---|
| 01 | Micro SMA/EMA crosses |
| 02 | EMA trend + filters |
| 03 | MACD / momentum regime |
| 04 | RSI mean-reversion identity |
| 05 | Donchian / ATR breakouts |
| 06 | Maximalist templates + layered risk |

Steal freely. Keep your core theory. Fib windows only. Files start with `strategy`.
