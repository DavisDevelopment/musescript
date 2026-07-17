#!/usr/bin/env python3
"""Crypto + FX tournament harness with strict causal next-open execution.

Official evaluation remains the same fixed three-calendar-month window as the
equity tournament. Signals observe bar t only after any pending order from t-1
has filled at bar t open; orders requested on t fill at t+1 open.
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[3]
KALSHAI = ROOT.parents[1]
ADVISOR_PYTHON = KALSHAI / "kalshi-ai-advisor" / "python"
TOURNAMENT = Path(__file__).resolve().parents[1]
TAPES = TOURNAMENT / "tapes-crypto-fx"
RESULTS = TOURNAMENT / "results"
RUNNER = ROOT / "build" / "js" / "gene-runner.js"

EVAL_START = "2026-04-14"
EVAL_END = "2026-07-13"
EXECUTION = "next-open"

ASSETS = {
    "BTCUSD": "crypto",
    "ETHUSD": "crypto",
    "SOLUSD": "crypto",
    "XRPUSD": "crypto",
    "ADAUSD": "crypto",
    "EURUSD": "forex",
    "GBPUSD": "forex",
    "USDJPY": "forex",
    "AUDUSD": "forex",
    "USDCAD": "forex",
}

# Every stability sample is itself exactly three calendar months.
WF_WINDOWS = [
    ("2019-01-02", "2019-04-01"),
    ("2022-01-03", "2022-04-02"),
    ("2024-10-01", "2024-12-31"),
]
WF_ASSETS = {"BTCUSD": "crypto", "ETHUSD": "crypto", "EURUSD": "forex"}


@dataclass
class Metrics:
    ok: bool
    bars: int = 0
    trades: int = 0
    sharpe: float = 0.0
    max_drawdown: float = 0.0
    win_rate: float = 0.0
    final_equity: float = 0.0
    execution: str = ""
    error: str = ""

    @property
    def total_return(self) -> float:
        return self.final_equity / 100_000.0 - 1.0 if self.final_equity > 0 else 0.0


def _provider_imports():
    if str(ADVISOR_PYTHON) not in sys.path:
        sys.path.insert(0, str(ADVISOR_PYTHON))
    from crawling.providers import fetch_bars

    return fetch_bars


def _validate_rows(
    symbol: str,
    asset: str,
    rows: list[dict],
    start: str,
    end: str,
    *,
    official: bool,
) -> dict:
    if not rows:
        raise ValueError(f"{symbol}: empty tape")
    dates = [str(r["date"])[:10] for r in rows]
    if dates != sorted(dates):
        raise ValueError(f"{symbol}: dates are not sorted")
    if len(dates) != len(set(dates)):
        raise ValueError(f"{symbol}: duplicate dates")
    if dates[0] < start or dates[-1] > end:
        raise ValueError(f"{symbol}: row outside {start}..{end}")
    if official and (dates[0] > start or dates[-1] < end):
        # FX can legitimately have no weekend bar at either boundary. Permit a
        # two-day boundary gap, but never a row from the future.
        from datetime import date

        start_gap = (date.fromisoformat(dates[0]) - date.fromisoformat(start)).days
        end_gap = (date.fromisoformat(end) - date.fromisoformat(dates[-1])).days
        if start_gap > 2 or end_gap > 2:
            raise ValueError(f"{symbol}: incomplete official window ({dates[0]}..{dates[-1]})")

    nonflat = 0
    sources: set[str] = set()
    provenances: set[str] = set()
    for row in rows:
        o, h, l, c = (float(row[k]) for k in ("open", "high", "low", "close"))
        if min(o, h, l, c) <= 0 or l > min(o, c) or h < max(o, c):
            raise ValueError(f"{symbol}: malformed OHLC on {row['date']}")
        if h > l:
            nonflat += 1
        sources.add(str(row.get("source") or ""))
        provenances.add(str(row.get("provenance") or ""))

    min_bars = 85 if asset == "crypto" and official else 55 if official else 40
    if len(rows) < min_bars:
        raise ValueError(f"{symbol}: only {len(rows)} bars (need {min_bars})")
    if official and "mid_as_ohlc" in provenances:
        raise ValueError(f"{symbol}: ECB mid_as_ohlc is not eligible for official scoring")
    if official and nonflat < max(20, len(rows) // 2):
        raise ValueError(f"{symbol}: insufficient real OHLC range ({nonflat}/{len(rows)} non-flat)")

    return {
        "symbol": symbol,
        "asset": asset,
        "bars": len(rows),
        "start": dates[0],
        "end": dates[-1],
        "sources": sorted(sources),
        "provenances": sorted(provenances),
        "nonflat_bars": nonflat,
        "causal": True,
    }


def _fetch_rows(symbol: str, asset: str, start: str, end: str) -> list[dict]:
    fetch_bars = _provider_imports()
    bars = fetch_bars(asset, symbol, interval="1d", start=start, end=end, min_bars=20)
    return [
        {
            "symbol": symbol,
            "date": b.date[:10],
            "open": b.open,
            "high": b.high,
            "low": b.low,
            "close": b.close,
            "volume": b.volume,
            "asset": asset,
            "source": b.source,
            "provenance": b.provenance,
        }
        for b in bars
    ]


def _write_tape(path: Path, rows: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "symbol", "date", "open", "high", "low", "close", "volume",
        "asset", "source", "provenance",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def build_tapes() -> dict:
    manifest = {
        "domain": "crypto+forex",
        "eval_window": {"start": EVAL_START, "end": EVAL_END, "calendar_months": 3},
        "execution": {
            "mode": EXECUTION,
            "signal": "bar_t_close",
            "fill": "bar_t_plus_1_open",
            "same_bar_fill": False,
        },
        "official": {},
        "walkforward": {},
    }
    for symbol, asset in ASSETS.items():
        rows = _fetch_rows(symbol, asset, EVAL_START, EVAL_END)
        audit = _validate_rows(symbol, asset, rows, EVAL_START, EVAL_END, official=True)
        path = TAPES / f"eval_3m_{symbol}.csv"
        _write_tape(path, rows)
        audit["path"] = str(path.relative_to(TOURNAMENT)).replace("\\", "/")
        manifest["official"][symbol] = audit

    for window_i, (start, end) in enumerate(WF_WINDOWS, 1):
        for symbol, asset in WF_ASSETS.items():
            rows = _fetch_rows(symbol, asset, start, end)
            audit = _validate_rows(symbol, asset, rows, start, end, official=False)
            path = TAPES / f"wf_{window_i}_{symbol}_{start}_{end}.csv"
            _write_tape(path, rows)
            audit["path"] = str(path.relative_to(TOURNAMENT)).replace("\\", "/")
            manifest["walkforward"][f"{window_i}:{symbol}"] = audit

    TAPES.mkdir(parents=True, exist_ok=True)
    (TAPES / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def run_backtest(source: Path, tape: Path, timeout: int = 60) -> Metrics:
    cmd = [
        "node", str(RUNNER), "--source", str(source), "--tape", str(tape),
        "--target", "js", "--execution", EXECUTION,
    ]
    try:
        proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return Metrics(ok=False, error="timeout")
    lines = (proc.stdout or "").strip().splitlines()
    if not lines:
        return Metrics(ok=False, error=(proc.stderr or "no output")[:300])
    try:
        data = json.loads(lines[-1])
    except json.JSONDecodeError:
        return Metrics(ok=False, error=lines[-1][:300])
    if not data.get("ok"):
        return Metrics(ok=False, error=str(data.get("error", data))[:300])
    if data.get("execution") != EXECUTION:
        return Metrics(ok=False, error="runner did not confirm causal next-open execution")
    return Metrics(
        ok=True,
        bars=int(data.get("bars") or 0),
        trades=int(data.get("trades") or 0),
        sharpe=float(data.get("sharpe") or 0),
        max_drawdown=float(data.get("maxDrawdown") or 0),
        win_rate=float(data.get("winRate") or 0),
        final_equity=float(data.get("finalEquity") or 0),
        execution=str(data.get("execution") or ""),
    )


def _buy_hold_source() -> Path:
    path = TAPES / "_buy_hold.ms"
    path.write_text(
        "strategy BuyHold {\n"
        "  onBar { when bar_index == 0: long() }\n"
        "}\n",
        encoding="utf-8",
    )
    return path


def eval_strategy(path: Path, symbols: list[str] | None = None, include_score: bool = True) -> dict:
    syms = symbols or list(ASSETS)
    bh_path = _buy_hold_source()
    per_symbol: dict[str, dict] = {}
    sharpes: list[float] = []
    deltas: list[float] = []
    mdds: list[float] = []
    for symbol in syms:
        tape = TAPES / f"eval_3m_{symbol}.csv"
        if not tape.exists():
            continue
        result = run_backtest(path, tape)
        buy_hold = run_backtest(bh_path, tape)
        per_symbol[symbol] = {
            **asdict(result),
            "asset": ASSETS[symbol],
            "return": result.total_return if result.ok else None,
            "bh_sharpe": buy_hold.sharpe if buy_hold.ok else None,
            "d_sharpe": result.sharpe - buy_hold.sharpe if result.ok and buy_hold.ok else None,
        }
        if result.ok:
            sharpes.append(result.sharpe)
            mdds.append(result.max_drawdown)
            if buy_hold.ok:
                deltas.append(result.sharpe - buy_hold.sharpe)

    out = {
        "strategy": path.name,
        "domain": "crypto+forex",
        "execution": EXECUTION,
        "eval_window": f"{EVAL_START}..{EVAL_END}",
        "mean_sharpe": statistics.fmean(sharpes) if sharpes else None,
        "mean_d_sharpe": statistics.fmean(deltas) if deltas else None,
        "median_mdd": statistics.median(mdds) if mdds else None,
        "symbols_tested": len(sharpes),
        "per_symbol": per_symbol,
    }
    if include_score:
        out["wf_mean_sharpe"] = eval_walkforward(path)
        out["score"] = score_entry(out)
    return out


def eval_walkforward(path: Path) -> float | None:
    sharpes: list[float] = []
    for window_i, (start, end) in enumerate(WF_WINDOWS, 1):
        for symbol in WF_ASSETS:
            tape = TAPES / f"wf_{window_i}_{symbol}_{start}_{end}.csv"
            if not tape.exists():
                continue
            result = run_backtest(path, tape)
            if result.ok:
                sharpes.append(result.sharpe)
    return statistics.fmean(sharpes) if sharpes else None


def annotate_activity(entry: dict) -> None:
    """Attach trade-activity fields used by the anti-cash-gaming score."""
    per = entry.get("per_symbol") or {}
    traded = [v for v in per.values() if (v.get("trades") or 0) > 0]
    entry["total_trades"] = sum((v.get("trades") or 0) for v in per.values())
    entry["active_symbols"] = len(traded)
    entry["crypto_active"] = sum(
        1 for sym, v in per.items() if ASSETS.get(sym) == "crypto" and (v.get("trades") or 0) > 0
    )
    entry["forex_active"] = sum(
        1 for sym, v in per.items() if ASSETS.get(sym) == "forex" and (v.get("trades") or 0) > 0
    )
    if traded:
        entry["traded_mean_sharpe"] = statistics.fmean(v.get("sharpe") or 0.0 for v in traded)
        deltas = [v["d_sharpe"] for v in traded if v.get("d_sharpe") is not None]
        entry["traded_mean_d_sharpe"] = statistics.fmean(deltas) if deltas else 0.0
    else:
        entry["traded_mean_sharpe"] = 0.0
        entry["traded_mean_d_sharpe"] = 0.0
    # Sitting in cash while BH is negative inflates mean_d_sharpe. Official score
    # therefore requires real participation across both asset classes.
    entry["eligible"] = (
        entry["active_symbols"] >= 4
        and entry["crypto_active"] >= 1
        and entry["forex_active"] >= 1
        and entry["total_trades"] >= 8
    )


def score_entry(entry: dict) -> float:
    annotate_activity(entry)
    mdd = entry.get("median_mdd")
    legacy = (
        0.40 * (entry.get("mean_sharpe") or 0.0)
        + 0.25 * (entry.get("mean_d_sharpe") or 0.0)
        + 0.20 * (1.0 - min(mdd if mdd is not None else 1.0, 1.0))
        + 0.15 * (entry.get("wf_mean_sharpe") or 0.0)
    )
    entry["legacy_score"] = legacy
    # Traded-only excess + breadth term. Ineligible rows keep a diagnostic score
    # but sort below every eligible strategy in score_all.
    adj = (
        0.35 * (entry.get("traded_mean_sharpe") or 0.0)
        + 0.25 * (entry.get("traded_mean_d_sharpe") or 0.0)
        + 0.15 * (1.0 - min(mdd if mdd is not None else 1.0, 1.0))
        + 0.15 * (entry.get("wf_mean_sharpe") or 0.0)
        + 0.10 * min(1.0, (entry.get("active_symbols") or 0) / 6.0)
    )
    return adj


def score_all(round_name: str) -> dict:
    rows: list[dict] = []
    for agent_dir in sorted((TOURNAMENT / "agents").glob("agent-*")):
        strategy_dir = agent_dir / round_name
        if not strategy_dir.exists():
            continue
        # Official submissions only — ignore _probe*.ms scratch files.
        for strategy in sorted(strategy_dir.glob("s0*.ms")):
            row = eval_strategy(strategy)
            row.update(
                agent=agent_dir.name,
                round=round_name,
                path=str(strategy.relative_to(TOURNAMENT)).replace("\\", "/"),
            )
            rows.append(row)
    rows.sort(
        key=lambda row: (
            1 if row.get("eligible") else 0,
            row.get("score") or 0.0,
        ),
        reverse=True,
    )
    out_dir = RESULTS / round_name
    out_dir.mkdir(parents=True, exist_ok=True)
    out = {
        "domain": "crypto+forex",
        "execution": EXECUTION,
        "eval_window": f"{EVAL_START}..{EVAL_END}",
        "round": round_name,
        "score_policy": {
            "eligible_min_active_symbols": 4,
            "eligible_min_trades": 8,
            "eligible_require_crypto_and_forex": True,
            "metrics": "traded-only sharpe / d_sharpe + breadth + WF",
        },
        "rankings": rows,
    }
    (out_dir / "leaderboard-crypto-fx.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    lines = [
        f"# Crypto + FX Tournament — {round_name}",
        "",
        f"Eval: **{EVAL_START} to {EVAL_END}** · execution: **{EXECUTION}** (no same-bar fills)",
        "",
        "Eligibility: ≥4 active symbols, ≥8 trades, ≥1 crypto + ≥1 FX. Cash-vs-BH farming is not crowned.",
        "",
        "| rank | agent | strategy | score | legacy | sharpe* | vs BH* | active | trades | eligible | WF |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---|---:|",
    ]
    for rank, row in enumerate(rows, 1):
        lines.append(
            f"| {rank} | {row['agent']} | {row['strategy']} | {row['score']:.3f} | "
            f"{(row.get('legacy_score') or 0):.3f} | {(row.get('traded_mean_sharpe') or 0):.3f} | "
            f"{(row.get('traded_mean_d_sharpe') or 0):+.3f} | {row.get('active_symbols') or 0} | "
            f"{row.get('total_trades') or 0} | {'yes' if row.get('eligible') else 'no'} | "
            f"{(row.get('wf_mean_sharpe') or 0):.3f} |"
        )
    eligible = [row for row in rows if row.get("eligible")]
    if eligible:
        winner = eligible[0]
        lines.extend([
            "", "## Winner (eligible)", "",
            f"**{winner['agent']} / {winner['strategy']}** — score {winner['score']:.3f} "
            f"(legacy {winner.get('legacy_score', 0):.3f}, "
            f"{winner.get('active_symbols')} symbols / {winner.get('total_trades')} trades)",
        ])
    elif rows:
        winner = rows[0]
        lines.extend([
            "", "## Winner", "",
            f"**{winner['agent']} / {winner['strategy']}** — {winner['score']:.3f} (no eligible strategies)",
        ])
    (out_dir / "LEADERBOARD-CRYPTO-FX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Causal crypto + FX tournament harness")
    parser.add_argument("--build-tapes", action="store_true")
    parser.add_argument("--eval")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--score-all", action="store_true")
    parser.add_argument("--round", default="round-07")
    args = parser.parse_args()

    if args.build_tapes:
        print(json.dumps(build_tapes(), indent=2))
        return 0
    if not (TAPES / "manifest.json").exists():
        raise SystemExit("missing crypto/FX tapes; run --build-tapes with the advisor venv")
    if args.eval:
        path = Path(args.eval)
        if not path.is_absolute():
            path = ROOT / path
        symbols = [args.symbol] if args.symbol else None
        print(json.dumps(eval_strategy(path, symbols), indent=2))
        return 0
    if args.score_all:
        print(json.dumps(score_all(args.round), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
