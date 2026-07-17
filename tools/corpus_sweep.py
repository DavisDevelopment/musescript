#!/usr/bin/env python3
"""Aggressive Fib-ladder grid sweep — hunt max OOS Sharpe / Calmar."""

from __future__ import annotations

import itertools
import json
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from corpus_lab import (  # noqa: E402
    RESULTS,
    STRATEGIES,
    TAPES,
    annotate_file,
    evaluate,
    run_backtest,
    split_spy,
    write_summary,
)

FIB = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]


@dataclass
class Candidate:
    name: str
    source: str
    hypothesis: str
    is_s: float
    oos_s: float
    oos_mdd: float
    oos_ret: float
    oos_calmar: float
    late_s: float
    late_mdd: float
    is_trades: int
    oos_trades: int
    oos_d_sharpe: float


def ema_cross_time(fast: int, slow: int, tstop: int | None) -> str:
    pos = ""
    if tstop is not None:
        pos = f"""
  onPosition {{
    when bars_in_trade >= {tstop}: flat()
  }}"""
    return f"""strategy S {{
  fast = ema(close, {fast})
  slow = ema(close, {slow})
  onBar {{
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }}{pos}
}}
"""


def ema_cross_trend_time(fast: int, slow: int, trend: int, tstop: int | None) -> str:
    pos = ""
    if tstop is not None:
        pos = f"""
  onPosition {{
    when bars_in_trade >= {tstop}: flat()
  }}"""
    return f"""strategy S {{
  fast = ema(close, {fast})
  slow = ema(close, {slow})
  trend = sma(close, {trend})
  onBar {{
    when close > trend && crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
    when close < trend: flat()
  }}{pos}
}}
"""


def ema_cross_macd_time(fast: int, slow: int, tstop: int | None) -> str:
    pos = ""
    if tstop is not None:
        pos = f"""
  onPosition {{
    when bars_in_trade >= {tstop}: flat()
  }}"""
    return f"""strategy S {{
  fast = ema(close, {fast})
  slow = ema(close, {slow})
  onBar {{
    m = macd(close, 13, 34, 8)
    when crossover(fast, slow) && m.hist > 0: long()
    when crossunder(fast, slow): flat()
    when m.hist < 0: flat()
  }}{pos}
}}
"""


def ema_cross_slow_exit(fast: int, slow: int, exit_len: int, tstop: int | None) -> str:
    pos = ""
    if tstop is not None:
        pos = f"""
  onPosition {{
    when bars_in_trade >= {tstop}: flat()
  }}"""
    return f"""strategy S {{
  fast = ema(close, {fast})
  slow = ema(close, {slow})
  exitMa = ema(close, {exit_len})
  onBar {{
    when crossover(fast, slow): long()
    when crossunder(fast, exitMa): flat()
  }}{pos}
}}
"""


def ema_cross_hard_stop(fast: int, slow: int, tstop: int | None, pct: float) -> str:
    pos = f"""
  onPosition {{
    when unrealized_pnl < -{pct} * equity: flat()"""
    if tstop is not None:
        pos += f"""
    when bars_in_trade >= {tstop}: flat()"""
    pos += """
  }"""
    return f"""strategy S {{
  fast = ema(close, {fast})
  slow = ema(close, {slow})
  onBar {{
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }}{pos}
}}
"""


def sma_cross_time(fast: int, slow: int, tstop: int | None) -> str:
    pos = ""
    if tstop is not None:
        pos = f"""
  onPosition {{
    when bars_in_trade >= {tstop}: flat()
  }}"""
    return f"""strategy S {{
  maFast = sma(close, {fast})
  maSlow = sma(close, {slow})
  onBar {{
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }}{pos}
}}
"""


def run_source(source: str) -> tuple:
    with tempfile.NamedTemporaryFile("w", suffix=".ms", delete=False, encoding="utf-8") as f:
        f.write(source)
        path = Path(f.name)
    try:
        is_m = run_backtest(path, TAPES / "spy_is_1993_2018.csv")
        oos_m = run_backtest(path, TAPES / "spy_oos_2019_2026.csv")
        late_m = run_backtest(path, TAPES / "spy_oos_2022_2026.csv")
        return is_m, oos_m, late_m
    finally:
        path.unlink(missing_ok=True)


def main() -> int:
    split_spy()
    bh = STRATEGIES / "00_buy_hold.ms"
    bh_is = run_backtest(bh, TAPES / "spy_is_1993_2018.csv")
    bh_oos = run_backtest(bh, TAPES / "spy_oos_2019_2026.csv")
    bh_late = run_backtest(bh, TAPES / "spy_oos_2022_2026.csv")
    print(f"BH  IS={bh_is.sharpe:.3f} OOS={bh_oos.sharpe:.3f} late={bh_late.sharpe:.3f}")

    hits: list[Candidate] = []
    pairs = [(f, s) for f in FIB for s in FIB if f < s]
    tstops = [None] + FIB

    # --- family 1: plain EMA + optional time stop ---
    for fast, slow in pairs:
        for tstop in tstops:
            src = ema_cross_time(fast, slow, tstop)
            is_m, oos_m, late_m = run_source(src)
            if not (is_m.ok and oos_m.ok and late_m.ok):
                continue
            if oos_m.trades < 5:
                continue
            name = f"ema_{fast}_{slow}_t{tstop or 'x'}"
            hits.append(
                Candidate(
                    name=name,
                    source=src.replace("strategy S", f"strategy {name}", 1),
                    hypothesis=f"EMA {fast}/{slow}" + (f" + {tstop}bar stop" if tstop else ""),
                    is_s=is_m.sharpe,
                    oos_s=oos_m.sharpe,
                    oos_mdd=oos_m.max_drawdown,
                    oos_ret=oos_m.total_return,
                    oos_calmar=oos_m.calmar,
                    late_s=late_m.sharpe,
                    late_mdd=late_m.max_drawdown,
                    is_trades=is_m.trades,
                    oos_trades=oos_m.trades,
                    oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                )
            )

    # --- family 2: EMA + trend filter (top pairs only) ---
    top_pairs = [(8, 21), (13, 21), (8, 13), (13, 34), (5, 13), (21, 34), (5, 8), (3, 8)]
    for fast, slow in top_pairs:
        for trend in [34, 55, 89]:
            for tstop in [None, 21, 34, 55]:
                src = ema_cross_trend_time(fast, slow, trend, tstop)
                is_m, oos_m, late_m = run_source(src)
                if not (is_m.ok and oos_m.ok and late_m.ok) or oos_m.trades < 5:
                    continue
                name = f"ema_{fast}_{slow}_tr{trend}_t{tstop or 'x'}"
                hits.append(
                    Candidate(
                        name=name,
                        source=src.replace("strategy S", f"strategy {name}", 1),
                        hypothesis=f"EMA {fast}/{slow} above SMA{trend}" + (f" + {tstop}bar" if tstop else ""),
                        is_s=is_m.sharpe,
                        oos_s=oos_m.sharpe,
                        oos_mdd=oos_m.max_drawdown,
                        oos_ret=oos_m.total_return,
                        oos_calmar=oos_m.calmar,
                        late_s=late_m.sharpe,
                        late_mdd=late_m.max_drawdown,
                        is_trades=is_m.trades,
                        oos_trades=oos_m.trades,
                        oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                    )
                )

    # --- family 3: EMA + MACD gate ---
    for fast, slow in top_pairs:
        for tstop in [None, 21, 34, 55]:
            src = ema_cross_macd_time(fast, slow, tstop)
            is_m, oos_m, late_m = run_source(src)
            if not (is_m.ok and oos_m.ok and late_m.ok) or oos_m.trades < 5:
                continue
            name = f"ema_{fast}_{slow}_macd_t{tstop or 'x'}"
            hits.append(
                Candidate(
                    name=name,
                    source=src.replace("strategy S", f"strategy {name}", 1),
                    hypothesis=f"EMA {fast}/{slow} + MACD hist>0" + (f" + {tstop}bar" if tstop else ""),
                    is_s=is_m.sharpe,
                    oos_s=oos_m.sharpe,
                    oos_mdd=oos_m.max_drawdown,
                    oos_ret=oos_m.total_return,
                    oos_calmar=oos_m.calmar,
                    late_s=late_m.sharpe,
                    late_mdd=late_m.max_drawdown,
                    is_trades=is_m.trades,
                    oos_trades=oos_m.trades,
                    oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                )
            )

    # --- family 4: slow EMA exit ---
    for fast, slow in top_pairs:
        for exit_len in [21, 34, 55]:
            if exit_len <= slow:
                continue
            for tstop in [None, 34, 55]:
                src = ema_cross_slow_exit(fast, slow, exit_len, tstop)
                is_m, oos_m, late_m = run_source(src)
                if not (is_m.ok and oos_m.ok and late_m.ok) or oos_m.trades < 5:
                    continue
                name = f"ema_{fast}_{slow}_ex{exit_len}_t{tstop or 'x'}"
                hits.append(
                    Candidate(
                        name=name,
                        source=src.replace("strategy S", f"strategy {name}", 1),
                        hypothesis=f"EMA {fast}/{slow} exit vs EMA{exit_len}" + (f" + {tstop}bar" if tstop else ""),
                        is_s=is_m.sharpe,
                        oos_s=oos_m.sharpe,
                        oos_mdd=oos_m.max_drawdown,
                        oos_ret=oos_m.total_return,
                        oos_calmar=oos_m.calmar,
                        late_s=late_m.sharpe,
                        late_mdd=late_m.max_drawdown,
                        is_trades=is_m.trades,
                        oos_trades=oos_m.trades,
                        oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                    )
                )

    # --- family 5: hard stop combos on best EMA pairs ---
    for fast, slow in [(8, 21), (13, 21), (5, 13), (8, 13)]:
        for pct in [0.04, 0.05, 0.06, 0.08]:
            for tstop in [None, 34, 55]:
                src = ema_cross_hard_stop(fast, slow, tstop, pct)
                is_m, oos_m, late_m = run_source(src)
                if not (is_m.ok and oos_m.ok and late_m.ok) or oos_m.trades < 5:
                    continue
                name = f"ema_{fast}_{slow}_hs{int(pct*100)}_t{tstop or 'x'}"
                hits.append(
                    Candidate(
                        name=name,
                        source=src.replace("strategy S", f"strategy {name}", 1),
                        hypothesis=f"EMA {fast}/{slow} + {int(pct*100)}% stop" + (f" + {tstop}bar" if tstop else ""),
                        is_s=is_m.sharpe,
                        oos_s=oos_m.sharpe,
                        oos_mdd=oos_m.max_drawdown,
                        oos_ret=oos_m.total_return,
                        oos_calmar=oos_m.calmar,
                        late_s=late_m.sharpe,
                        late_mdd=late_m.max_drawdown,
                        is_trades=is_m.trades,
                        oos_trades=oos_m.trades,
                        oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                    )
                )

    # --- family 6: SMA crosses with time stop (fast subset) ---
    sma_pairs = [(f, s) for f, s in pairs if f <= 21 and s <= 55]
    for fast, slow in sma_pairs:
        for tstop in [None, 21, 34, 55]:
            src = sma_cross_time(fast, slow, tstop)
            is_m, oos_m, late_m = run_source(src)
            if not (is_m.ok and oos_m.ok and late_m.ok) or oos_m.trades < 5:
                continue
            name = f"sma_{fast}_{slow}_t{tstop or 'x'}"
            hits.append(
                Candidate(
                    name=name,
                    source=src.replace("strategy S", f"strategy {name}", 1),
                    hypothesis=f"SMA {fast}/{slow}" + (f" + {tstop}bar" if tstop else ""),
                    is_s=is_m.sharpe,
                    oos_s=oos_m.sharpe,
                    oos_mdd=oos_m.max_drawdown,
                    oos_ret=oos_m.total_return,
                    oos_calmar=oos_m.calmar,
                    late_s=late_m.sharpe,
                    late_mdd=late_m.max_drawdown,
                    is_trades=is_m.trades,
                    oos_trades=oos_m.trades,
                    oos_d_sharpe=oos_m.sharpe - bh_oos.sharpe,
                )
            )

    print(f"\nSwept {len(hits)} viable configs")

    by_oos = sorted(hits, key=lambda c: c.oos_s, reverse=True)[:15]
    by_calmar = sorted(hits, key=lambda c: c.oos_calmar, reverse=True)[:15]
    by_late = sorted(hits, key=lambda c: c.late_s, reverse=True)[:15]
    by_combo = sorted(hits, key=lambda c: (c.oos_s, c.late_s, -c.oos_mdd), reverse=True)[:15]

    def dump(title: str, rows: list[Candidate]) -> None:
        print(f"\n=== {title} ===")
        for c in rows:
            print(
                f"  {c.name:32s} IS={c.is_s:5.3f} OOS={c.oos_s:5.3f} "
                f"d={c.oos_d_sharpe:+.3f} mdd={c.oos_mdd:.3f} cal={c.oos_calmar:.1f} "
                f"late={c.late_s:.3f} tr={c.oos_trades}"
            )

    dump("TOP OOS SHARPE", by_oos)
    dump("TOP OOS CALMAR", by_calmar)
    dump("TOP LATE SHARPE", by_late)
    dump("TOP COMBO", by_combo)

    # Save top 8 unique combos as corpus strategies 30+
    seen_src = set()
    saved = []
    for c in by_combo:
        key = (round(c.oos_s, 4), round(c.oos_mdd, 4))
        if key in seen_src:
            continue
        seen_src.add(key)
        idx = 30 + len(saved)
        fname = f"{idx:02d}_{c.name}.ms"
        path = STRATEGIES / fname
        path.write_text(c.source.strip() + "\n", encoding="utf-8")
        entry = evaluate(path, c.hypothesis, bh_is, bh_oos, notes=f"sweep rank; late sharpe={c.late_s:.4f}")
        saved.append((fname, c, entry))
        if len(saved) >= 8:
            break

    write_summary(bh_is, bh_oos)
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "sweep_top.json").write_text(
        json.dumps(
            [
                {
                    "rank": i + 1,
                    "file": f,
                    "name": c.name,
                    "hypothesis": c.hypothesis,
                    "is_sharpe": c.is_s,
                    "oos_sharpe": c.oos_s,
                    "oos_mdd": c.oos_mdd,
                    "oos_calmar": c.oos_calmar,
                    "late_sharpe": c.late_s,
                    "late_mdd": c.late_mdd,
                    "oos_d_sharpe": c.oos_d_sharpe,
                    "transfers": e.get("transfers_oos"),
                }
                for i, (f, c, e) in enumerate(saved)
            ],
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\nSaved {len(saved)} sweep winners to corpus/strategies/30+")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
