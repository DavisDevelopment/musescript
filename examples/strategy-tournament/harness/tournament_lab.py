#!/usr/bin/env python3
"""Tournament harness — all official eval on 3-month tapes only."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOURNAMENT = Path(__file__).resolve().parents[1]
TAPES = TOURNAMENT / "tapes"
RESULTS = TOURNAMENT / "results"
RUNNER = ROOT / "build" / "js" / "gene-runner.js"
SOURCE_TAPE = ROOT / "data" / "real" / "tape.csv"
SOURCE_SPY = ROOT / "data" / "real" / "spy.csv"

# Fixed 3-month eval window (calendar); ~63 trading days.
EVAL_START = "2026-04-14"
EVAL_END = "2026-07-13"

SYMBOLS = [
    "SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "META", "AMZN", "GOOGL",
]

# Walk-forward: three consecutive 3-month OOS eras (for final scoring only).
WF_WINDOWS = [
    ("2019-01-02", "2019-04-01"),
    ("2022-01-03", "2022-04-01"),
    ("2024-10-01", "2024-12-31"),
]


@dataclass
class Metrics:
    ok: bool
    bars: int = 0
    trades: int = 0
    sharpe: float = 0.0
    max_drawdown: float = 0.0
    win_rate: float = 0.0
    final_equity: float = 0.0
    error: str = ""

    @property
    def total_return(self) -> float:
        return self.final_equity / 100_000.0 - 1.0 if self.final_equity > 0 else 0.0


def run_backtest(source: Path, tape: Path, symbol: str = "", timeout: int = 60) -> Metrics:
    if not RUNNER.exists():
        return Metrics(ok=False, error=f"missing runner: {RUNNER}")
    cmd = ["node", str(RUNNER), "--source", str(source), "--tape", str(tape), "--target", "js"]
    if symbol:
        cmd.extend(["--symbol", symbol])
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
    return Metrics(
        ok=True,
        bars=int(data.get("bars") or 0),
        trades=int(data.get("trades") or 0),
        sharpe=float(data.get("sharpe") or 0),
        max_drawdown=float(data.get("maxDrawdown") or 0),
        win_rate=float(data.get("winRate") or 0),
        final_equity=float(data.get("finalEquity") or 0),
    )


def slice_tape(rows: list[dict], start: str, end: str) -> list[dict]:
    return [r for r in rows if start <= r["date"] <= end]


def write_tape(path: Path, rows: list[dict], header: list[str]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    return len(rows)


def build_eval_tapes() -> dict:
    by_sym: dict[str, list[dict]] = {s: [] for s in SYMBOLS}
    header = None
    with SOURCE_TAPE.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        header = list(reader.fieldnames or [])
        for row in reader:
            sym = row.get("symbol", "")
            if sym in by_sym:
                by_sym[sym].append(row)

    info = {"eval_3m": {}, "wf": {}}
    for sym in SYMBOLS:
        rows = by_sym[sym]
        if not rows:
            continue
        h = header or list(rows[0].keys())
        eval_rows = slice_tape(rows, EVAL_START, EVAL_END)
        p = TAPES / f"eval_3m_{sym}.csv"
        n = write_tape(p, eval_rows, h)
        info["eval_3m"][sym] = {"path": str(p.relative_to(TOURNAMENT)), "bars": n, "start": EVAL_START, "end": EVAL_END}

    for i, (ws, we) in enumerate(WF_WINDOWS):
        for sym in ["SPY", "QQQ", "AAPL"]:
            rows = by_sym.get(sym, [])
            if not rows:
                continue
            h = header or list(rows[0].keys())
            wf_rows = slice_tape(rows, ws, we)
            p = TAPES / f"wf_{i+1}_{sym}_{ws}_{we}.csv"
            n = write_tape(p, wf_rows, h)
            info["wf"][f"{sym}_{i+1}"] = {"path": str(p.relative_to(TOURNAMENT)), "bars": n, "start": ws, "end": we}

    manifest = {
        "eval_window": {"start": EVAL_START, "end": EVAL_END, "note": "Official tournament scoring — 3 months only"},
        "symbols": SYMBOLS,
        "tapes": info,
    }
    TAPES.mkdir(parents=True, exist_ok=True)
    (TAPES / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def buy_hold_source() -> str:
    return """strategy BuyHold {
  onBar {
    when bar_index == 1: long()
  }
}
"""


def eval_strategy(path: Path, symbols: list[str] | None = None) -> dict:
    syms = symbols or SYMBOLS
    per_sym = {}
    sharpes = []
    d_sharpes = []
    mdds = []
    bh_path = TAPES / "_buy_hold.ms"
    bh_path.write_text(buy_hold_source(), encoding="utf-8")
    for sym in syms:
        tape = TAPES / f"eval_3m_{sym}.csv"
        if not tape.exists():
            continue
        m = run_backtest(path, tape)
        bh = run_backtest(bh_path, tape)
        per_sym[sym] = {
            "sharpe": m.sharpe if m.ok else None,
            "mdd": m.max_drawdown if m.ok else None,
            "trades": m.trades if m.ok else None,
            "ret": m.total_return if m.ok else None,
            "bh_sharpe": bh.sharpe if bh.ok else None,
            "d_sharpe": (m.sharpe - bh.sharpe) if m.ok and bh.ok else None,
            "error": m.error if not m.ok else None,
        }
        if m.ok:
            sharpes.append(m.sharpe)
            mdds.append(m.max_drawdown)
            if bh.ok:
                d_sharpes.append(m.sharpe - bh.sharpe)
    return {
        "strategy": path.name,
        "eval_window": f"{EVAL_START}..{EVAL_END}",
        "mean_sharpe": sum(sharpes) / len(sharpes) if sharpes else None,
        "mean_d_sharpe": sum(d_sharpes) / len(d_sharpes) if d_sharpes else None,
        "median_mdd": sorted(mdds)[len(mdds) // 2] if mdds else None,
        "symbols_tested": len(sharpes),
        "per_symbol": per_sym,
    }


def score_entry(entry: dict) -> float:
    wf_sharpes = entry.get("wf_mean_sharpe")
    wf_part = wf_sharpes if wf_sharpes is not None else entry.get("mean_sharpe") or 0
    mdd = entry.get("median_mdd") or 1.0
    return (
        0.40 * (entry.get("mean_sharpe") or 0)
        + 0.25 * (entry.get("mean_d_sharpe") or 0)
        + 0.20 * (1.0 - min(mdd, 1.0))
        + 0.15 * wf_part
    )


def eval_walkforward(path: Path) -> float | None:
    bh_path = TAPES / "_buy_hold.ms"
    if not bh_path.exists():
        bh_path.write_text(buy_hold_source(), encoding="utf-8")
    sharpes = []
    for i, (ws, we) in enumerate(WF_WINDOWS):
        for sym in ["SPY", "QQQ", "AAPL"]:
            tape = TAPES / f"wf_{i+1}_{sym}_{ws}_{we}.csv"
            if not tape.exists():
                continue
            m = run_backtest(path, tape)
            if m.ok:
                sharpes.append(m.sharpe)
    return sum(sharpes) / len(sharpes) if sharpes else None


def eval_all_agents(round_name: str = "strategies") -> dict:
    agents_dir = TOURNAMENT / "agents"
    rows = []
    for agent_dir in sorted(agents_dir.glob("agent-*")):
        strat_dir = agent_dir / round_name
        if not strat_dir.exists():
            continue
        for strat in sorted(strat_dir.glob("*.ms")):
            if strat.name.startswith("_"):
                continue
            r = eval_strategy(strat)
            r["agent"] = agent_dir.name
            r["round"] = round_name
            r["path"] = str(strat.relative_to(TOURNAMENT)).replace("\\", "/")
            r["wf_mean_sharpe"] = eval_walkforward(strat)
            r["score"] = score_entry(r)
            rows.append(r)
    rows.sort(key=lambda x: x["score"], reverse=True)
    round_num = round_name.replace("round-", "") if round_name.startswith("round-") else round_name
    out_dir = RESULTS / f"round-{round_num}" if round_name.startswith("round-") else RESULTS
    out_dir.mkdir(parents=True, exist_ok=True)
    out = {"eval_window": f"{EVAL_START}..{EVAL_END}", "round": round_name, "rankings": rows}
    (out_dir / "leaderboard.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    lines = [
        f"# Tournament Leaderboard — {round_name}",
        "",
        f"Eval window: **{EVAL_START} to {EVAL_END}** (3 months only)",
        "",
        "| rank | agent | strategy | score | mean_sharpe | mean_d_sharpe | median_mdd | wf_sharpe |",
        "|---:|---|---|---:|---:|---:|---:|---:|",
    ]
    for i, r in enumerate(rows[:30], 1):
        lines.append(
            f"| {i} | {r['agent']} | {r['strategy']} | {r['score']:.3f} | "
            f"{(r.get('mean_sharpe') or 0):.3f} | {(r.get('mean_d_sharpe') or 0):+.3f} | "
            f"{(r.get('median_mdd') or 0):.3f} | {(r.get('wf_mean_sharpe') or 0):.3f} |"
        )
    if rows:
        w = rows[0]
        lines += [
            "",
            "## Winner",
            "",
            f"**{w['agent']} / {w['strategy']}** — score {w['score']:.3f}",
            f"- 3m mean Sharpe: {w.get('mean_sharpe', 0):.3f}",
            f"- vs buy-hold: {w.get('mean_d_sharpe', 0):+.3f}",
        ]
    (out_dir / "LEADERBOARD.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    # Also refresh latest symlink-style copy at results root for backward compat
    if round_name.startswith("round-"):
        (RESULTS / "leaderboard.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
        (RESULTS / "LEADERBOARD.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Tournament harness (3-month eval only)")
    ap.add_argument("--build-tapes", action="store_true")
    ap.add_argument("--eval", type=str, help="Evaluate one strategy .ms path")
    ap.add_argument("--symbol", type=str, default="", help="Single symbol for --eval")
    ap.add_argument("--score-all", action="store_true", help="Score all agents (organizer)")
    ap.add_argument("--round", type=str, default="round-01", help="Round folder name, e.g. round-02")
    args = ap.parse_args()

    if args.build_tapes or not (TAPES / "manifest.json").exists():
        manifest = build_eval_tapes()
        print(json.dumps(manifest, indent=2))

    if args.eval:
        path = Path(args.eval)
        if not path.is_absolute():
            path = ROOT / path
        syms = [args.symbol] if args.symbol else None
        print(json.dumps(eval_strategy(path, syms), indent=2))
        return 0

    if args.score_all:
        print(json.dumps(eval_all_agents(args.round), indent=2))
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
