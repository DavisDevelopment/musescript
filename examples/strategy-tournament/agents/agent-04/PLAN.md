# Agent 04 — Mean Reversion Ranger

## Hypothesis

Short-window RSI mean reversion (dip-buy and recovery-cross entries) produces positive risk-adjusted returns when gated by an intermediate trend filter. In the official 3-month eval window (~62 daily bars), trend filters must use Fib windows ≤ 55 so indicators warm up inside the tape; SMA/EMA 89 from the seed brief are reserved for walk-forward eras with longer history.

**Core edge:** buy temporary weakness (RSI pullback) only while price holds above a rising trend line; exit on RSI normalization, trend break, or hard/time stops.

## Strategy lineup

| File | Entry logic | Trend filter | Exit / risk |
|------|-------------|--------------|-------------|
| `s01.ms` | RSI(13) < 42 dip | EMA(34) | RSI > 65 or close < EMA34 |
| `s02.ms` | RSI(13) < 42 dip | EMA(55) | RSI > 68, trend break, 3% equity stop |
| `s03.ms` | RSI(8) recovery cross above 35 | EMA(21) | RSI > 62, trend break, 13-bar time stop |
| `s04.ms` | RSI(13) < 45 dip | EMA(8) > EMA(21) stack | RSI > 60, stack break, 4% stop |
| `s05.ms` | RSI(13) cross-down below 44 | EMA(34) | RSI > 68, trend break, 4% stop + 21-bar time stop |

## Iteration approach

1. **Compile check** — every file must start with `strategy`, use `&&`/`||`, Fib window lengths only.
2. **SPY smoke test** — `tournament_lab.py --eval ... --symbol SPY` on the 3m tape; zero-trade strategies are rejected.
3. **Threshold sweep** — classic RSI(13) < 30 + SMA(89) produced no trades on 62-bar tapes (SMA89 never warms; bull window rarely hits deep oversold). Relaxed to RSI 42–45 entries and EMA(21)/EMA(34) trends.
4. **Entry style variants** — level dip (`r < 42`), recovery cross (`r > 35 && r[1] <= 35`), momentum stack (`fast > slow`), and cross-down (`r < 44 && r[1] >= 44`).
5. **Cross-symbol sanity** — optional 10-symbol eval to spot single-name blowups (NVDA/META mean-reversion traps).

## Risk controls

- **Trend gate:** no long entries when price is below the slow trend MA/EMA.
- **RSI exits:** take profit when RSI reverts toward 60–68 (not waiting for full overbought).
- **Hard stops (`onPosition`):** 3–5% of equity via `unrealized_pnl` on s02, s04, s05.
- **Time stops:** Fib 13-bar cap on s03, Fib 21-bar cap on s05 to limit dead-money holds.
- **Position discipline:** `position() == 0` on entries; flat on trend/stack breakdown.

## Self-test command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/strategies/s03.ms --symbol SPY
```

## Expected tournament posture

- **Best candidate:** `s03.ms` — RSI(8) recovery cross; highest SPY Sharpe (1.03) and only positive 10-symbol mean Sharpe (+0.08).
- **ETF bias:** s03 works on SPY/QQQ/IWM; single names with violent trends (NVDA) punish mean reversion.
- **Weakness:** none of the five beat buy-and-hold Sharpe on SPY in this bull 3m window; edge is drawdown control and cross-symbol diversification, not raw return.
