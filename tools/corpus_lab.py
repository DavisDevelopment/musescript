#!/usr/bin/env python3
"""Corpus lab: split tapes, backtest MuseScript strategies, annotate + ledger."""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "corpus"
STRATEGIES = CORPUS / "strategies"
TAPES = CORPUS / "tapes"
RESULTS = CORPUS / "results"
LEDGER = RESULTS / "ledger.jsonl"
SUMMARY = RESULTS / "SUMMARY.md"
RUNNER = ROOT / "build" / "js" / "gene-runner.js"
DEFAULT_SOURCE = ROOT / "data" / "real" / "spy.csv"

# In-sample ends at end of 2018; OOS is 2019+ (includes COVID + bull).
IS_END = "2018-12-31"
OOS_START = "2019-01-01"


@dataclass
class Metrics:
    ok: bool
    bars: int = 0
    trades: int = 0
    sharpe: float = 0.0
    max_drawdown: float = 0.0
    win_rate: float = 0.0
    final_equity: float = 0.0
    backend: str = ""
    error: str = ""

    @property
    def total_return(self) -> float:
        if self.final_equity <= 0:
            return 0.0
        return self.final_equity / 100_000.0 - 1.0

    @property
    def calmar(self) -> float:
        if self.max_drawdown <= 1e-12:
            return 0.0
        return self.total_return / self.max_drawdown


def ensure_dirs() -> None:
    for p in (CORPUS, STRATEGIES, TAPES, RESULTS):
        p.mkdir(parents=True, exist_ok=True)


def split_spy(source: Path = DEFAULT_SOURCE) -> dict[str, Path]:
    ensure_dirs()
    rows = list(csv.DictReader(source.open(newline="", encoding="utf-8")))
    header = list(rows[0].keys()) if rows else [
        "symbol", "date", "open", "high", "low", "close", "volume"
    ]

    def write(name: str, pred) -> Path:
        path = TAPES / name
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=header)
            w.writeheader()
            for r in rows:
                if pred(r["date"]):
                    w.writerow(r)
        return path

    full = write("spy_full.csv", lambda d: True)
    is_path = write("spy_is_1993_2018.csv", lambda d: d <= IS_END)
    oos_path = write("spy_oos_2019_2026.csv", lambda d: d >= OOS_START)
    # Early OOS holdout inside the bull (2022+) as a second check
    late = write("spy_oos_2022_2026.csv", lambda d: d >= "2022-01-01")
    return {
        "full": full,
        "is": is_path,
        "oos": oos_path,
        "oos_late": late,
        "n_full": len(rows),
        "n_is": sum(1 for r in rows if r["date"] <= IS_END),
        "n_oos": sum(1 for r in rows if r["date"] >= OOS_START),
    }


def run_backtest(source: Path, tape: Path, target: str = "js", timeout: int = 120) -> Metrics:
    if not RUNNER.exists():
        return Metrics(ok=False, error=f"missing runner: {RUNNER}")
    cmd = [
        "node",
        str(RUNNER),
        "--source",
        str(source),
        "--tape",
        str(tape),
        "--target",
        target,
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return Metrics(ok=False, error="timeout")
    out = (proc.stdout or "").strip().splitlines()
    if not out:
        err = (proc.stderr or proc.stdout or "no output").strip()
        return Metrics(ok=False, error=err[:500])
    try:
        data = json.loads(out[-1])
    except json.JSONDecodeError:
        return Metrics(ok=False, error=out[-1][:500])
    if not data.get("ok"):
        return Metrics(ok=False, error=str(data.get("error") or data)[:500])
    return Metrics(
        ok=True,
        bars=int(data.get("bars") or 0),
        trades=int(data.get("trades") or 0),
        sharpe=float(data.get("sharpe") or 0),
        max_drawdown=float(data.get("maxDrawdown") or 0),
        win_rate=float(data.get("winRate") or 0),
        final_equity=float(data.get("finalEquity") or 0),
        backend=str(data.get("backend") or target),
    )


ANNOTATION_RE = re.compile(
    r"\n*/\*\s*CORPUS_BACKTEST\s*.*?\*/\s*",
    re.DOTALL,
)


def format_annotation(
    hypothesis: str,
    is_m: Metrics,
    oos_m: Metrics,
    bh_is: Metrics | None,
    bh_oos: Metrics | None,
    notes: str = "",
) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def row(label: str, m: Metrics) -> str:
        if not m.ok:
            return f"  {label}: FAIL {m.error}"
        return (
            f"  {label}: sharpe={m.sharpe:.4f} mdd={m.max_drawdown:.4f} "
            f"ret={m.total_return:.4f} calmar={m.calmar:.4f} "
            f"trades={m.trades} equity={m.final_equity:.2f} bars={m.bars}"
        )

    def delta(label: str, m: Metrics, bh: Metrics | None) -> str:
        if not m.ok or bh is None or not bh.ok:
            return f"  vs_bh_{label}: n/a"
        return (
            f"  vs_bh_{label}: d_sharpe={m.sharpe - bh.sharpe:+.4f} "
            f"d_mdd={m.max_drawdown - bh.max_drawdown:+.4f} "
            f"d_ret={m.total_return - bh.total_return:+.4f}"
        )

    transfers = False
    reason = "no"
    if is_m.ok and oos_m.ok and bh_is and bh_oos and bh_is.ok and bh_oos.ok:
        oos_edge = (oos_m.sharpe > bh_oos.sharpe + 0.05) or (
            oos_m.calmar > bh_oos.calmar * 1.1 and oos_m.max_drawdown < bh_oos.max_drawdown
        )
        strong_oos = oos_m.sharpe > bh_oos.sharpe + 0.20
        is_ok = (
            is_m.sharpe >= bh_is.sharpe * 0.85
            or is_m.calmar >= bh_is.calmar
            or (is_m.sharpe >= 0.45 and is_m.total_return > 1.0)
            or (strong_oos and is_m.sharpe >= 0.35 and is_m.total_return > 1.0)
        )
        oos_risk = (
            oos_m.max_drawdown < bh_oos.max_drawdown * 0.75
            and oos_m.total_return >= bh_oos.total_return * 0.7
            and oos_m.sharpe >= bh_oos.sharpe * 0.95
        )
        transfers = bool((oos_edge or oos_risk) and is_ok and oos_m.trades >= 2)
        if transfers:
            reason = "yes"
        elif oos_edge and not is_ok:
            reason = "oos_only"
        elif is_ok and not oos_edge and not oos_risk:
            reason = "is_only"

    lines = [
        "/* CORPUS_BACKTEST",
        f"  generated: {now}",
        f"  tape_is: spy_is_1993_2018 (<= {IS_END})",
        f"  tape_oos: spy_oos_2019_2026 (>= {OOS_START})",
        f"  hypothesis: {hypothesis}",
        row("IS", is_m),
        row("OOS", oos_m),
        delta("IS", is_m, bh_is),
        delta("OOS", oos_m, bh_oos),
        f"  transfers_oos: {reason}",
    ]
    if notes:
        lines.append(f"  notes: {notes}")
    lines.append("*/")
    lines.append("")
    return "\n".join(lines)


def strip_body(source: str) -> str:
    return ANNOTATION_RE.sub("", source).lstrip()


def annotate_file(
    path: Path,
    hypothesis: str,
    is_m: Metrics,
    oos_m: Metrics,
    bh_is: Metrics | None,
    bh_oos: Metrics | None,
    notes: str = "",
) -> None:
    # Annotation MUST trail the source: StrategyParser.looksLike only accepts
    # files that start with `strategy`/`template`/… after ltrim.
    body = strip_body(path.read_text(encoding="utf-8")).rstrip() + "\n"
    ann = format_annotation(hypothesis, is_m, oos_m, bh_is, bh_oos, notes)
    path.write_text(body + "\n" + ann, encoding="utf-8", newline="\n")


def append_ledger(entry: dict) -> None:
    ensure_dirs()
    with LEDGER.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def write_summary(bh_is: Metrics, bh_oos: Metrics) -> None:
    rows = []
    if LEDGER.exists():
        for line in LEDGER.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rows.append(json.loads(line))
    # Keep latest per strategy
    latest: dict[str, dict] = {}
    for r in rows:
        latest[r["name"]] = r

    lines = [
        "# MuseScript strategy corpus",
        "",
        f"Split: IS `<= {IS_END}`, OOS `>= {OOS_START}` on SPY daily.",
        "",
        "## Buy-hold baseline",
        "",
        f"- IS: sharpe={bh_is.sharpe:.4f} mdd={bh_is.max_drawdown:.4f} "
        f"ret={bh_is.total_return:.4f} equity={bh_is.final_equity:.2f}",
        f"- OOS: sharpe={bh_oos.sharpe:.4f} mdd={bh_oos.max_drawdown:.4f} "
        f"ret={bh_oos.total_return:.4f} equity={bh_oos.final_equity:.2f}",
        "",
        "## Strategies (latest run)",
        "",
        "| name | IS sharpe | OOS sharpe | OOS dSharpe | OOS MDD | transfers |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for name in sorted(latest):
        r = latest[name]
        def fmt(v, spec=".3f"):
            return format(v, spec) if isinstance(v, (int, float)) else "—"

        lines.append(
            f"| {name} | {fmt(r.get('is_sharpe'))} | {fmt(r.get('oos_sharpe'))} | "
            f"{fmt(r.get('oos_d_sharpe'), '+.3f')} | {fmt(r.get('oos_mdd'))} | "
            f"{r.get('transfers_oos', '?')} |"
        )
    winners = [r for r in latest.values() if r.get("transfers_oos") == "yes"]
    lines += ["", "## OOS-transferring edges", ""]
    if winners:
        for w in winners:
            lines.append(
                f"- **{w['name']}**: OOS sharpe {w['oos_sharpe']:.3f} "
                f"(Δ {w['oos_d_sharpe']:+.3f}), MDD {w['oos_mdd']:.3f} — {w.get('hypothesis', '')}"
            )
    else:
        lines.append("_None yet._")
    SUMMARY.write_text("\n".join(lines) + "\n", encoding="utf-8")


def evaluate(
    path: Path,
    hypothesis: str,
    bh_is: Metrics,
    bh_oos: Metrics,
    notes: str = "",
    target: str = "js",
) -> dict:
    is_tape = TAPES / "spy_is_1993_2018.csv"
    oos_tape = TAPES / "spy_oos_2019_2026.csv"
    is_m = run_backtest(path, is_tape, target=target)
    oos_m = run_backtest(path, oos_tape, target=target)
    annotate_file(path, hypothesis, is_m, oos_m, bh_is, bh_oos, notes)

    # Parse transfers from annotation
    text = path.read_text(encoding="utf-8")
    m = re.search(r"transfers_oos:\s*(\S+)", text)
    transfers = m.group(1) if m else "?"

    entry = {
        "name": path.stem,
        "path": str(path.relative_to(ROOT)).replace("\\", "/"),
        "hypothesis": hypothesis,
        "notes": notes,
        "is_sharpe": is_m.sharpe if is_m.ok else None,
        "is_mdd": is_m.max_drawdown if is_m.ok else None,
        "is_ret": is_m.total_return if is_m.ok else None,
        "is_trades": is_m.trades if is_m.ok else None,
        "oos_sharpe": oos_m.sharpe if oos_m.ok else None,
        "oos_mdd": oos_m.max_drawdown if oos_m.ok else None,
        "oos_ret": oos_m.total_return if oos_m.ok else None,
        "oos_trades": oos_m.trades if oos_m.ok else None,
        "oos_d_sharpe": (oos_m.sharpe - bh_oos.sharpe) if oos_m.ok and bh_oos.ok else None,
        "oos_d_mdd": (oos_m.max_drawdown - bh_oos.max_drawdown) if oos_m.ok and bh_oos.ok else None,
        "transfers_oos": transfers,
        "is_ok": is_m.ok,
        "oos_ok": oos_m.ok,
        "is_error": is_m.error,
        "oos_error": oos_m.error,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    append_ledger(entry)
    return entry


def write_strategy(name: str, body: str) -> Path:
    ensure_dirs()
    path = STRATEGIES / f"{name}.ms"
    path.write_text(body.strip() + "\n", encoding="utf-8", newline="\n")
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--split-only", action="store_true")
    ap.add_argument("--eval", type=str, help="Evaluate one .ms path")
    ap.add_argument("--hypothesis", type=str, default="")
    ap.add_argument("--notes", type=str, default="")
    args = ap.parse_args()

    ensure_dirs()
    info = split_spy()
    print(json.dumps({k: (str(v) if isinstance(v, Path) else v) for k, v in info.items()}))

    if args.split_only:
        return 0

    bh = STRATEGIES / "00_buy_hold.ms"
    if not bh.exists():
        write_strategy(
            "00_buy_hold",
            """
strategy BuyHold {
  onBar {
    when bar_index == 50: long()
  }
}
""",
        )

    bh_is = run_backtest(bh, TAPES / "spy_is_1993_2018.csv")
    bh_oos = run_backtest(bh, TAPES / "spy_oos_2019_2026.csv")
    print("BH_IS", bh_is)
    print("BH_OOS", bh_oos)

    if args.eval:
        path = Path(args.eval)
        if not path.is_absolute():
            path = ROOT / path
        entry = evaluate(path, args.hypothesis or path.stem, bh_is, bh_oos, args.notes)
        write_summary(bh_is, bh_oos)
        print(json.dumps(entry, indent=2))
        return 0 if entry.get("is_ok") and entry.get("oos_ok") else 1

    write_summary(bh_is, bh_oos)
    return 0


if __name__ == "__main__":
    sys.exit(main())
