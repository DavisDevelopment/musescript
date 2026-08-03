#!/usr/bin/env python3
"""Flagship matrix evaluator — wraps gene-runner across batches × windows × honesty × frequency.

MuseScript has no multi-file imports yet, so this harness stitches lib/*.ms + the
strategy source into a temp file before each backtest.

Examples:
  python examples/flagship-musescript-module/harness/eval.py --check
  python examples/flagship-musescript-module/harness/eval.py --build-tapes
  python examples/flagship-musescript-module/harness/eval.py --eval --batch liquid10 --window eval_3m
  python examples/flagship-musescript-module/harness/eval.py --optimize --symbol SPY --window eval_3m
  python examples/flagship-musescript-module/harness/eval.py --matrix
  python examples/flagship-musescript-module/harness/eval.py --matrix --quick
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
FLAGSHIP = Path(__file__).resolve().parents[1]
LIB = FLAGSHIP / "lib"
STRATEGIES = FLAGSHIP / "strategies"
CONFIGS = FLAGSHIP / "configs"
TAPES = FLAGSHIP / "tapes"
RESULTS = FLAGSHIP / "results"
RUNNER = ROOT / "build" / "js" / "gene-runner.js"
SOURCE_TAPE = ROOT / "data" / "real" / "tape.csv"
DEFAULT_STRATEGY = STRATEGIES / "flagship_v5h.ms"


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
    trades_per_bar: float = 0.0

    @property
    def total_return(self) -> float:
        return self.final_equity / 100_000.0 - 1.0 if self.final_equity > 0 else 0.0


@dataclass
class CellResult:
    batch: str
    window: str
    honesty: str
    frequency: str
    symbol: str
    metrics: Metrics
    bh_sharpe: float | None = None
    d_sharpe: float | None = None
    freq_ok: bool = True
    pass_cell: bool = False


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def stitch_source(strategy: Path, lib_dir: Path = LIB) -> str:
    parts: list[str] = []
    if lib_dir.exists():
        for p in sorted(lib_dir.glob("*.ms")):
            parts.append(f"// ---- lib/{p.name} ----\n")
            parts.append(p.read_text(encoding="utf-8").rstrip() + "\n\n")
    parts.append(f"// ---- strategy/{strategy.name} ----\n")
    parts.append(strategy.read_text(encoding="utf-8").rstrip() + "\n")
    return "".join(parts)


def ensure_runner() -> None:
    if not RUNNER.exists():
        print(f"missing {RUNNER.relative_to(ROOT)} — building via haxe build-cli.hxml …", file=sys.stderr)
        subprocess.run(["haxe", "build-cli.hxml"], cwd=str(ROOT), check=True)
    if not RUNNER.exists():
        raise SystemExit(f"gene-runner still missing after build: {RUNNER}")


def run_gene_raw(
    source_text: str,
    tape: Path | None,
    *,
    symbol: str = "",
    execution: str = "next-open",
    cost_bps: float = 10.0,
    check_only: bool = False,
    optimize: bool = False,
    metric: str = "sharpe",
    method: str = "grid",
    min_trades: int = 1,
    seed: int = 42,
    timeout: int = 180,
) -> dict[str, Any]:
    """Shell gene-runner; return parsed JSON object (or ok:false envelope)."""
    ensure_runner()
    with tempfile.NamedTemporaryFile("w", suffix=".ms", delete=False, encoding="utf-8") as tmp:
        tmp.write(source_text)
        src_path = Path(tmp.name)
    try:
        cmd = ["node", str(RUNNER), "--source", str(src_path), "--target", "js", "--seed", str(seed)]
        if check_only:
            cmd.append("--check")
        elif optimize:
            if tape is None:
                return {"ok": False, "error": "optimize requires a tape"}
            cmd.extend(
                [
                    "--optimize",
                    "--tape",
                    str(tape),
                    "--execution",
                    execution,
                    "--cost-bps",
                    str(cost_bps),
                    "--metric",
                    metric,
                    "--method",
                    method,
                    "--min-trades",
                    str(min_trades),
                ]
            )
            if symbol:
                cmd.extend(["--symbol", symbol])
        else:
            if tape is None:
                return {"ok": False, "error": "backtest requires a tape"}
            cmd.extend(
                [
                    "--tape",
                    str(tape),
                    "--execution",
                    execution,
                    "--cost-bps",
                    str(cost_bps),
                ]
            )
            if symbol:
                cmd.extend(["--symbol", symbol])
        try:
            proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "timeout"}
        lines = (proc.stdout or "").strip().splitlines()
        if not lines:
            return {"ok": False, "error": (proc.stderr or "no output")[:400]}
        try:
            return json.loads(lines[-1])
        except json.JSONDecodeError:
            return {"ok": False, "error": lines[-1][:400]}
    finally:
        src_path.unlink(missing_ok=True)


def run_gene(
    source_text: str,
    tape: Path,
    *,
    symbol: str = "",
    execution: str = "next-open",
    cost_bps: float = 10.0,
    check_only: bool = False,
    timeout: int = 90,
) -> Metrics:
    data = run_gene_raw(
        source_text,
        tape if not check_only else None,
        symbol=symbol,
        execution=execution,
        cost_bps=cost_bps,
        check_only=check_only,
        timeout=timeout,
    )
    if not data.get("ok"):
        err = data.get("error") or data.get("reason") or data
        return Metrics(ok=False, error=str(err)[:400])
    if check_only:
        return Metrics(ok=True)
    bars = int(data.get("bars") or 0)
    trades = int(data.get("trades") or 0)
    return Metrics(
        ok=True,
        bars=bars,
        trades=trades,
        sharpe=float(data.get("sharpe") or 0),
        max_drawdown=float(data.get("maxDrawdown") or 0),
        win_rate=float(data.get("winRate") or 0),
        final_equity=float(data.get("finalEquity") or 0),
        trades_per_bar=(trades / bars) if bars > 0 else 0.0,
    )


def buy_hold_source() -> str:
    return "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"


def frequency_match(m: Metrics, freq: dict[str, Any]) -> bool:
    if not m.ok:
        return False
    return (
        freq["min_trades"] <= m.trades <= freq["max_trades"]
        and freq["min_trades_per_bar"] <= m.trades_per_bar <= freq["max_trades_per_bar"]
    )


def classify_frequency(m: Metrics, frequencies: dict[str, Any]) -> str:
    """Best-matching named band (excluding 'any')."""
    best = "unclassified"
    for name, spec in frequencies.items():
        if name == "any":
            continue
        if frequency_match(m, spec):
            best = name
            break
    return best


def slice_rows(rows: list[dict], start: str | None, end: str | None) -> list[dict]:
    if not start and not end:
        return rows
    out = []
    for r in rows:
        d = r.get("date", "")
        if start and d < start:
            continue
        if end and d > end:
            continue
        out.append(r)
    return out


def write_tape(path: Path, rows: list[dict], header: list[str]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    return len(rows)


def build_tapes(windows: dict[str, Any], batches: dict[str, Any]) -> dict[str, Any]:
    if not SOURCE_TAPE.exists():
        raise SystemExit(f"missing source tape: {SOURCE_TAPE} — run .\\run.ps1 fetch-ohlcv")

    needed: set[str] = set()
    for b in batches.values():
        needed.update(b["symbols"])

    by_sym: dict[str, list[dict]] = {s: [] for s in needed}
    header: list[str] | None = None
    with SOURCE_TAPE.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        header = list(reader.fieldnames or [])
        for row in reader:
            sym = row.get("symbol", "")
            if sym in by_sym:
                by_sym[sym].append(row)

    info: dict[str, Any] = {"windows": {}, "symbols_found": {}}
    for sym, rows in by_sym.items():
        info["symbols_found"][sym] = len(rows)

    for wname, wspec in windows.items():
        info["windows"][wname] = {}
        for sym in sorted(needed):
            rows = by_sym.get(sym, [])
            if not rows:
                continue
            sliced = slice_rows(rows, wspec.get("start"), wspec.get("end"))
            if not sliced:
                continue
            h = header or list(sliced[0].keys())
            path = TAPES / wname / f"{sym}.csv"
            n = write_tape(path, sliced, h)
            info["windows"][wname][sym] = {"path": str(path.relative_to(FLAGSHIP)), "bars": n}

    TAPES.mkdir(parents=True, exist_ok=True)
    manifest = {
        "source": str(SOURCE_TAPE.relative_to(ROOT)),
        "tapes": info,
    }
    (TAPES / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def tape_for(window: str, symbol: str) -> Path | None:
    p = TAPES / window / f"{symbol}.csv"
    return p if p.exists() else None


def cell_passes(m: Metrics, bh_sharpe: float | None, freq_ok: bool) -> bool:
    """Hard gate: ok, positive edge vs cash, beats buy-hold Sharpe, freq band, controlled MDD."""
    if not m.ok or not freq_ok:
        return False
    if m.trades < 1:
        return False
    if m.sharpe <= 0:
        return False
    if m.max_drawdown > 0.25:
        return False
    if bh_sharpe is not None and m.sharpe <= bh_sharpe:
        return False
    return True


def eval_batch(
    source: str,
    *,
    batch_name: str,
    symbols: list[str],
    window: str,
    honesty_name: str,
    honesty: dict[str, Any],
    freq_name: str,
    freq: dict[str, Any],
    frequencies: dict[str, Any],
) -> list[CellResult]:
    bh = buy_hold_source()
    cells: list[CellResult] = []
    execution = honesty["execution"]
    cost_bps = float(honesty["cost_bps"])

    for sym in symbols:
        tape = tape_for(window, sym)
        if tape is None:
            cells.append(
                CellResult(
                    batch=batch_name,
                    window=window,
                    honesty=honesty_name,
                    frequency=freq_name,
                    symbol=sym,
                    metrics=Metrics(ok=False, error="missing tape"),
                    freq_ok=False,
                    pass_cell=False,
                )
            )
            continue
        m = run_gene(source, tape, execution=execution, cost_bps=cost_bps)
        bh_m = run_gene(bh, tape, execution=execution, cost_bps=cost_bps)
        bh_sharpe = bh_m.sharpe if bh_m.ok else None
        d_sharpe = (m.sharpe - bh_sharpe) if m.ok and bh_sharpe is not None else None
        freq_ok = frequency_match(m, freq) if freq_name != "any" else m.ok
        # For freq=any we still annotate the natural band.
        _ = classify_frequency(m, frequencies)
        cells.append(
            CellResult(
                batch=batch_name,
                window=window,
                honesty=honesty_name,
                frequency=freq_name,
                symbol=sym,
                metrics=m,
                bh_sharpe=bh_sharpe,
                d_sharpe=d_sharpe,
                freq_ok=freq_ok,
                pass_cell=cell_passes(m, bh_sharpe, freq_ok if freq_name != "any" else True),
            )
        )
    return cells


def summarize(cells: list[CellResult]) -> dict[str, Any]:
    ok_cells = [c for c in cells if c.metrics.ok]
    pass_cells = [c for c in cells if c.pass_cell]
    sharpes = [c.metrics.sharpe for c in ok_cells]
    d_sharpes = [c.d_sharpe for c in ok_cells if c.d_sharpe is not None]
    mdds = [c.metrics.max_drawdown for c in ok_cells]
    trades = [c.metrics.trades for c in ok_cells]
    rets = [c.metrics.total_return for c in ok_cells]

    def mean(xs: list[float], default: float = 0.0) -> float:
        return statistics.fmean(xs) if xs else default

    # Composite inspired by tournament_lab, plus pass-rate pressure.
    mean_sharpe = mean(sharpes)
    mean_d = mean(d_sharpes)
    mean_mdd = mean(mdds, default=1.0)
    pass_rate = (len(pass_cells) / len(cells)) if cells else 0.0
    score = (
        0.35 * mean_sharpe
        + 0.25 * mean_d
        + 0.15 * (1.0 - min(mean_mdd, 1.0))
        + 0.25 * pass_rate
    )

    by_sym = {
        c.symbol: {
            "ok": c.metrics.ok,
            "pass": c.pass_cell,
            "sharpe": c.metrics.sharpe if c.metrics.ok else None,
            "d_sharpe": c.d_sharpe,
            "mdd": c.metrics.max_drawdown if c.metrics.ok else None,
            "trades": c.metrics.trades if c.metrics.ok else None,
            "trades_per_bar": round(c.metrics.trades_per_bar, 4) if c.metrics.ok else None,
            "ret": round(c.metrics.total_return, 4) if c.metrics.ok else None,
            "freq_ok": c.freq_ok,
            "error": c.metrics.error or None,
        }
        for c in cells
    }

    return {
        "n_symbols": len(cells),
        "n_ok": len(ok_cells),
        "n_pass": len(pass_cells),
        "pass_rate": pass_rate,
        "mean_sharpe": mean_sharpe,
        "mean_d_sharpe": mean_d,
        "mean_mdd": mean_mdd,
        "mean_trades": mean([float(t) for t in trades]) if trades else None,
        "mean_return": mean(rets) if rets else None,
        "score": score,
        "by_symbol": by_sym,
    }


def print_summary(title: str, summary: dict[str, Any]) -> None:
    print(f"\n=== {title} ===")
    print(
        f"pass {summary['n_pass']}/{summary['n_symbols']} "
        f"({summary['pass_rate']:.0%})  "
        f"score={summary['score']:.3f}  "
        f"meanSharpe={summary['mean_sharpe']:.3f}  "
        f"dBH={summary['mean_d_sharpe']:.3f}  "
        f"mdd={summary['mean_mdd']:.3f}  "
        f"trades~={summary['mean_trades'] if summary['mean_trades'] is not None else 'n/a'}"
    )
    for sym, row in summary["by_symbol"].items():
        if not row["ok"]:
            print(f"  {sym:6} FAIL  {row['error']}")
            continue
        mark = "PASS" if row["pass"] else "weak"
        print(
            f"  {sym:6} {mark:4}  sharpe={row['sharpe']:+.3f}  "
            f"dBH={(row['d_sharpe'] or 0):+.3f}  "
            f"mdd={row['mdd']:.3f}  trades={row['trades']}  "
            f"tpb={row['trades_per_bar']:.3f}  ret={row['ret']:+.2%}"
        )


def cmd_optimize(args: argparse.Namespace) -> int:
    """Run HonestOptimize over the stitched module (pipeline tune/optimize + param ranges)."""
    windows = load_json(CONFIGS / "windows.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    batches = load_json(CONFIGS / "batches.json")
    if not (TAPES / "manifest.json").exists():
        print("tapes missing — building …")
        build_tapes(windows, batches)

    strategy = Path(args.strategy).resolve()
    source = stitch_source(strategy)
    honesty = honesty_cfg[args.honesty]
    tape = tape_for(args.window, args.symbol)
    if tape is None:
        print(f"missing tape for {args.window}/{args.symbol} — run --build-tapes")
        return 1

    data = run_gene_raw(
        source,
        tape,
        symbol=args.symbol,
        execution=honesty["execution"],
        cost_bps=float(honesty["cost_bps"]),
        optimize=True,
        metric=args.metric,
        method=args.method,
        min_trades=args.min_trades,
        seed=args.seed,
        timeout=args.timeout,
    )
    RESULTS.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS / f"optimize_{strategy.stem}_{args.symbol}_{args.window}_{args.honesty}.json"
    out_path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    print(f"=== optimize {strategy.name} on {args.symbol} / {args.window} / {args.honesty} ===")
    if not data.get("ok"):
        print(f"FAIL  {data.get('error') or data.get('reason') or data}")
        print(f"wrote {rel(out_path)}")
        return 1
    print(
        f"found={data.get('found')}  trials={data.get('trials')}  "
        f"survivors={data.get('survivors')}  rejected={data.get('rejected')}  "
        f"beatsNull={data.get('anyBeatsNull')}"
    )
    if data.get("reason"):
        print(f"reason: {data['reason']}")
    if data.get("message"):
        msg = str(data["message"]).replace("\u2014", "-").replace("\u2013", "-")
        print(f"message: {msg}")
    best = data.get("best")
    if best:
        print(f"best metric={best.get('metric')}  sharpe={best.get('sharpe')}  trades={best.get('trades')}")
        print(f"best params: {json.dumps(best.get('params'), sort_keys=True)}")
        tr = best.get("truthReport") or {}
        if tr:
            print(f"truth: verdict={tr.get('verdict')}  beatsNull={tr.get('beatsNull')}")
    print(f"wrote {rel(out_path)}")
    return 0 if data.get("found") else 2


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def cmd_check(strategy: Path) -> int:
    strategy = strategy.resolve()
    src = stitch_source(strategy)
    # Synthetic tape check path: --check only.
    m = run_gene(src, Path("."), check_only=True)
    if m.ok:
        print(f"CHECK OK  {rel(strategy)}  (stitched {len(src)} chars)")
        return 0
    print(f"CHECK FAIL  {m.error}")
    # Dump stitched source for debugging
    dump = RESULTS / "_last_stitched.ms"
    RESULTS.mkdir(parents=True, exist_ok=True)
    dump.write_text(src, encoding="utf-8")
    print(f"stitched source written to {rel(dump)}")
    return 1


def cmd_eval(args: argparse.Namespace) -> int:
    batches = load_json(CONFIGS / "batches.json")
    windows = load_json(CONFIGS / "windows.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    frequencies = load_json(CONFIGS / "frequencies.json")

    if not (TAPES / "manifest.json").exists():
        print("tapes missing — building …")
        build_tapes(windows, batches)

    strategy = Path(args.strategy).resolve()
    source = stitch_source(strategy)
    batch = batches[args.batch]
    window = args.window
    honesty = honesty_cfg[args.honesty]
    freq = frequencies[args.frequency]

    cells = eval_batch(
        source,
        batch_name=args.batch,
        symbols=batch["symbols"],
        window=window,
        honesty_name=args.honesty,
        honesty=honesty,
        freq_name=args.frequency,
        freq=freq,
        frequencies=frequencies,
    )
    summary = summarize(cells)
    title = f"{strategy.name} x {args.batch} x {window} x {args.honesty} x freq={args.frequency}"
    print_summary(title, summary)

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = {
        "strategy": rel(strategy),
        "batch": args.batch,
        "window": window,
        "honesty": args.honesty,
        "frequency": args.frequency,
        "summary": summary,
        "cells": [
            {
                **{k: getattr(c, k) for k in ("batch", "window", "honesty", "frequency", "symbol", "freq_ok", "pass_cell")},
                "bh_sharpe": c.bh_sharpe,
                "d_sharpe": c.d_sharpe,
                "metrics": asdict(c.metrics),
            }
            for c in cells
        ],
    }
    out_path = RESULTS / f"eval_{strategy.stem}_{args.batch}_{window}_{args.honesty}_{args.frequency}.json"
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"\nwrote {rel(out_path)}")
    return 0 if summary["n_pass"] == summary["n_symbols"] and summary["n_symbols"] > 0 else 2


def cmd_matrix(args: argparse.Namespace) -> int:
    batches = load_json(CONFIGS / "batches.json")
    windows = load_json(CONFIGS / "windows.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    frequencies = load_json(CONFIGS / "frequencies.json")

    if not (TAPES / "manifest.json").exists():
        print("tapes missing — building …")
        build_tapes(windows, batches)

    strategy = Path(args.strategy).resolve()
    source = stitch_source(strategy)

    if args.quick:
        batch_names = ["index3", "liquid10"]
        window_names = ["eval_3m", "wf_2022q1"]
        honesty_names = ["causal_realistic"]
        freq_names = ["any", "swing", "position"]
    else:
        batch_names = list(batches.keys()) if args.batches == "all" else [b.strip() for b in args.batches.split(",")]
        window_names = list(windows.keys()) if args.windows == "all" else [w.strip() for w in args.windows.split(",")]
        # Skip full-history by default unless explicitly requested — it's slow.
        if args.windows == "all":
            window_names = [w for w in window_names if w != "full"]
        honesty_names = (
            list(honesty_cfg.keys()) if args.honesty_modes == "all" else [h.strip() for h in args.honesty_modes.split(",")]
        )
        freq_names = (
            [f for f in frequencies if f != "idle"]
            if args.frequencies == "all"
            else [f.strip() for f in args.frequencies.split(",")]
        )

    matrix: list[dict[str, Any]] = []
    perfect = 0
    total = 0

    for b in batch_names:
        for w in window_names:
            for h in honesty_names:
                for f in freq_names:
                    total += 1
                    cells = eval_batch(
                        source,
                        batch_name=b,
                        symbols=batches[b]["symbols"],
                        window=w,
                        honesty_name=h,
                        honesty=honesty_cfg[h],
                        freq_name=f,
                        freq=frequencies[f],
                        frequencies=frequencies,
                    )
                    summary = summarize(cells)
                    title = f"{b} x {w} x {h} x freq={f}"
                    print_summary(title, summary)
                    row = {
                        "batch": b,
                        "window": w,
                        "honesty": h,
                        "frequency": f,
                        "summary": summary,
                    }
                    matrix.append(row)
                    if summary["n_pass"] == summary["n_symbols"] and summary["n_symbols"] > 0:
                        perfect += 1

    RESULTS.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS / f"matrix_{strategy.stem}.json"
    payload = {
        "strategy": rel(strategy),
        "perfect_cells": perfect,
        "total_cells": total,
        "coverage": perfect / total if total else 0.0,
        "matrix": matrix,
    }
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    # Leaderboard-style markdown
    md_lines = [
        f"# Flagship matrix — `{strategy.name}`",
        "",
        f"Perfect cells: **{perfect}/{total}** ({payload['coverage']:.0%})",
        "",
        "| Batch | Window | Honesty | Freq | Pass | Score | Mean Sharpe | dBH | MDD |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for row in sorted(matrix, key=lambda r: -r["summary"]["score"]):
        s = row["summary"]
        md_lines.append(
            f"| {row['batch']} | {row['window']} | {row['honesty']} | {row['frequency']} | "
            f"{s['n_pass']}/{s['n_symbols']} | {s['score']:.3f} | {s['mean_sharpe']:.3f} | "
            f"{s['mean_d_sharpe']:.3f} | {s['mean_mdd']:.3f} |"
        )
    md_path = RESULTS / f"matrix_{strategy.stem}.md"
    md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    print(f"\n=== MATRIX DONE  perfect={perfect}/{total} ===")
    print(f"wrote {rel(out_path)}")
    print(f"wrote {rel(md_path)}")
    return 0 if perfect == total and total > 0 else 2


def main() -> int:
    p = argparse.ArgumentParser(description="Flagship MuseScript strategy matrix evaluator")
    p.add_argument("--strategy", type=Path, default=DEFAULT_STRATEGY, help="Strategy .ms (libs auto-stitched)")
    p.add_argument("--check", action="store_true", help="Parse/typecheck stitched source only")
    p.add_argument("--build-tapes", action="store_true", help="Slice tapes from data/real/tape.csv")
    p.add_argument("--eval", action="store_true", help="Evaluate one batch x window x honesty x freq cell")
    p.add_argument("--optimize", action="store_true", help="HonestOptimize over pipeline/param tune holes")
    p.add_argument("--matrix", action="store_true", help="Sweep the configured matrix")
    p.add_argument("--quick", action="store_true", help="Smaller matrix for fast iteration")
    p.add_argument("--batch", default="liquid10")
    p.add_argument("--window", default="eval_3m")
    p.add_argument("--honesty", default="causal_realistic")
    p.add_argument("--frequency", default="any")
    p.add_argument("--symbol", default="SPY", help="Symbol for --optimize")
    p.add_argument("--metric", default="sharpe", help="Optimize metric")
    p.add_argument("--method", default="grid", help="Search method: grid|coordinate")
    p.add_argument("--min-trades", type=int, default=2, help="Min trades for honesty gate")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--timeout", type=int, default=300, help="Seconds for --optimize")
    p.add_argument("--batches", default="index3,liquid10,mega7,chip2", help="Comma list or 'all'")
    p.add_argument("--windows", default="eval_3m,wf_2019q1,wf_2022q1,wf_2024q4", help="Comma list or 'all'")
    p.add_argument("--honesty-modes", default="causal_realistic,causal_harsh", help="Comma list or 'all'")
    p.add_argument("--frequencies", default="any,position,swing,active", help="Comma list or 'all'")
    args = p.parse_args()

    if args.check:
        return cmd_check(args.strategy)
    if args.build_tapes:
        windows = load_json(CONFIGS / "windows.json")
        batches = load_json(CONFIGS / "batches.json")
        manifest = build_tapes(windows, batches)
        print(json.dumps(manifest, indent=2))
        return 0
    if args.optimize:
        return cmd_optimize(args)
    if args.matrix:
        return cmd_matrix(args)
    if args.eval:
        return cmd_eval(args)

    p.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
