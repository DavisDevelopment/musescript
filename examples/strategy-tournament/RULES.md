# Strategy Tournament Rules

## Sequestration

- Each agent works **only** in `agents/agent-XX/` (their assigned folder).
- **No reading** other agents' `PLAN.md` or `strategies/` until the organizer runs final evaluation.
- Shared code is limited to `harness/` and `tapes/` (read-only for agents).

## Evaluation window: **3 months only**

Official tournament scoring uses **exactly the last 3 calendar months** of daily bars per symbol.

- Window: `2026-04-14` through `2026-07-13` (inclusive)
- ~63 trading days per symbol
- Pre-built tapes: `tapes/eval_3m_<SYMBOL>.csv`

Agents may **not** use longer tapes for official self-scoring during the tournament. Design hypotheses however you like, but iterate using:

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval agents/agent-XX/strategies/your_strat.ms --symbol SPY
```

## Deliverables per agent

1. `PLAN.md` — hypothesis, iteration approach, risk controls
2. Exactly **5** MuseScript files in `strategies/` (`.ms`)

## MuseScript constraints

- File must **start** with `strategy` / `template` (no leading comments)
- Window lengths on Fib ladder: `1,2,3,5,8,13,21,34,55,89`
- Boolean ops: `&&` / `||` (not `and` / `or`)
- `onPosition { ... }` allowed for stops/time exits

## Scoring (organizer runs after lock)

Per strategy, on each eval symbol:

| component | weight |
|---|---:|
| Mean 3m Sharpe across symbols | 40% |
| Mean 3m Sharpe vs symbol buy-hold | 25% |
| Median 3m max drawdown (lower better) | 20% |
| Walk-forward stability (3m windows in 2019+) | 15% |

Best single strategy across all agents wins.

## Symbols

`SPY, QQQ, IWM, AAPL, MSFT, NVDA, AMD, META, AMZN, GOOGL`
