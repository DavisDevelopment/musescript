#!/usr/bin/env python3
"""Flagship grind observer core — publish helpers + scoring reused by agents/CLIs.

Primary contract: external agents / harness CLIs score strategies and call
`publish_*` (or write `results/viz_state.json` directly). The visualizer is an
observer over that artifact, not a CPU-burning suite launcher.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Callable

from eval import (
    CONFIGS,
    DEFAULT_STRATEGY,
    FLAGSHIP,
    Metrics,
    RESULTS,
    ROOT,
    RUNNER,
    STRATEGIES,
    buy_hold_source,
    cell_passes,
    ensure_runner,
    eval_batch,
    load_json,
    run_gene,
    run_gene_batch,
    stitch_source,
    summarize,
)

ProgressCb = Callable[[dict[str, Any]], None]

LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
AVAILABLE = LIQUID10 + ["JPM", "XOM", "TSLA", "BAC", "WMT"]
DUAL_WINDOWS = ["eval_3m", "wf_2022q1"]
BULL_WINDOWS = ["wf_2019q1", "wf_2024q4"]
CORPUS_WINDOWS = ["eval_3m", "wf_2022q1", "wf_2019q1", "wf_2024q4"]
SOFT_WALLS = {"QQQ", "AMD", "GOOGL", "NVDA"}
BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

# Promote bar relative to DEFAULT lineage dBH ~+1.58
PROMOTE = {
    "dual_min": 18,
    "bulls_min": 11,
    "corpus_pct_min": 55.0,
    "dbh_ref": 1.58,
    "dbh_floor": round(1.58 * 0.85, 2),  # ~1.34
}

# --- Resource bounds (hard rails) ---
BOUNDS = {
    "max_history": 80,
    "max_log_lines": 200,
    "max_cells_per_suite": 80,
    "max_state_bytes": 1_800_000,
    "watch_debounce_ms": 900,
    "watch_cooldown_s": 45,
    "max_workers": 1,  # never parallel cell stampede
    "equity_max_points": 600,  # downsample equity strip
}

STATE_PATH = RESULTS / "viz_state.json"
_pub_lock = threading.RLock()


def resolve_strategy(name_or_path: str | Path | None = None) -> Path:
    if name_or_path is None or str(name_or_path).strip() == "":
        return DEFAULT_STRATEGY
    p = Path(str(name_or_path))
    if p.is_file():
        return p.resolve()
    for cand in (
        STRATEGIES / p.name,
        STRATEGIES / p,
        FLAGSHIP / p,
        FLAGSHIP / "strategies" / p,
    ):
        if cand.is_file():
            return cand.resolve()
    raise FileNotFoundError(f"strategy not found: {name_or_path}")


def list_genomes() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    default_name = DEFAULT_STRATEGY.name
    seen: set[str] = set()
    candidates: list[Path] = []
    if DEFAULT_STRATEGY.is_file():
        candidates.append(DEFAULT_STRATEGY)
    for p in sorted(STRATEGIES.glob("flagship_v7*.ms")):
        candidates.append(p)
    for p in candidates:
        if p.name in seen:
            continue
        if "_known_good" in p.name:
            continue
        if p.name.startswith("_"):
            continue
        seen.add(p.name)
        st = p.stat()
        out.append(
            {
                "name": p.name,
                "path": str(p.relative_to(FLAGSHIP)).replace("\\", "/"),
                "stem": p.stem,
                "is_default": p.name == default_name,
                "mtime": st.st_mtime,
                "size": st.st_size,
            }
        )
    return out


def score_one(src: str, win: str, sym: str) -> dict[str, Any]:
    tape = FLAGSHIP / "tapes" / win / f"{sym}.csv"
    if not tape.exists():
        return {
            "symbol": sym,
            "window": win,
            "ok": False,
            "pass": False,
            "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
            "error": "missing tape",
            "d_sharpe": None,
            "sharpe": None,
            "bh_sharpe": None,
            "trades": None,
            "ret": None,
            "mdd": None,
        }
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    if not m.ok:
        return {
            "symbol": sym,
            "window": win,
            "ok": False,
            "pass": False,
            "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
            "error": m.error or "run failed",
            "d_sharpe": None,
            "sharpe": None,
            "bh_sharpe": bh.sharpe if bh.ok else None,
            "trades": None,
            "ret": None,
            "mdd": None,
        }
    bh_sh = bh.sharpe if bh.ok else None
    d = (m.sharpe - bh_sh) if bh_sh is not None else None
    passed = cell_passes(m, bh_sh, True)
    return {
        "symbol": sym,
        "window": win,
        "ok": True,
        "pass": passed,
        "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
        "error": None,
        "d_sharpe": round(d, 4) if d is not None else None,
        "sharpe": round(m.sharpe, 4),
        "bh_sharpe": round(bh_sh, 4) if bh_sh is not None else None,
        "trades": m.trades,
        "ret": round(m.total_return, 4),
        "mdd": round(m.max_drawdown, 4),
    }


def _emit(cb: ProgressCb | None, event: dict[str, Any]) -> None:
    if cb:
        cb(event)


# ---------------------------------------------------------------------------
# Observer publish API — agents / CLIs write; viz_server watches
# ---------------------------------------------------------------------------


def empty_job() -> dict[str, Any]:
    return {
        "running": False,
        "suite": None,
        "strategy": None,
        "done": 0,
        "total": 0,
        "error": None,
        "started_at": None,
        "trigger": None,
        "source": None,  # agent | cli | ui | disk
        "agent": None,
        "current": None,
        "last_cell": None,
        "n_pass": 0,
        "mean_d_sharpe": 0.0,
        "elapsed_s": 0.0,
        "eta_s": None,
        "pct": 0.0,
        "remaining": [],
        "remaining_n": 0,
        "history": [],
        "locked": False,
        "lock_reason": None,
    }


def empty_artifact() -> dict[str, Any]:
    return {
        "default": DEFAULT_STRATEGY.name,
        "runs": {},
        "job": empty_job(),
        "log": [],
        "focus": None,  # {stem, suite, symbol, window} — last focused cell
        "equity": None,  # last on-demand equity payload (single cell)
        "bounds": BOUNDS,
        "mode": "observe",
        "updated_at": None,
        "source": None,
    }


def _stem_of(strategy: str | Path | None) -> str:
    if strategy is None:
        return DEFAULT_STRATEGY.stem
    p = Path(str(strategy))
    name = p.name if p.suffix else str(strategy)
    return name.replace(".ms", "") if name.endswith(".ms") else Path(name).stem


def _job_timing(job: dict[str, Any]) -> None:
    started = job.get("started_at")
    if not started:
        job["elapsed_s"] = 0.0
        job["eta_s"] = None
        job["pct"] = 0.0
        return
    elapsed = max(time.time() - float(started), 0.001)
    done = int(job.get("done") or 0)
    total = int(job.get("total") or 0)
    job["elapsed_s"] = round(elapsed, 2)
    job["pct"] = round(100.0 * done / total, 1) if total else 0.0
    if done > 0 and total > done:
        job["eta_s"] = round((elapsed / done) * (total - done), 1)
    else:
        job["eta_s"] = 0.0 if total and done >= total else None


def _trim_suite(result: dict[str, Any]) -> dict[str, Any]:
    """Cap cells / matrix rows so viz_state.json stays bounded."""
    out = dict(result)
    cap = BOUNDS["max_cells_per_suite"]
    if isinstance(out.get("cells"), list) and len(out["cells"]) > cap:
        out["cells"] = out["cells"][-cap:]
        out["_truncated_cells"] = True
    if isinstance(out.get("matrix"), list) and len(out["matrix"]) > cap:
        # keep head (plan order matters for matrix)
        out["matrix"] = out["matrix"][:cap]
        out["_truncated_matrix"] = True
    # drop per-symbol bulk from matrix rows if huge
    for row in out.get("matrix") or []:
        bs = row.get("by_symbol")
        if isinstance(bs, dict) and len(bs) > 20:
            # keep keys only for soft walls + pass marks via summary — already have n_pass
            row["by_symbol"] = {k: bs[k] for k in list(bs)[:20]}
            row["_by_symbol_truncated"] = True
    return out


def _ensure_promote(bucket: dict[str, Any]) -> None:
    bucket["promote"] = promote_status(
        bucket.get("dual"),
        bucket.get("bulls"),
        bucket.get("corpus"),
    )
    walls = soft_wall_focus(bucket.get("bulls"))
    if walls:
        bucket["soft_walls"] = walls


def load_artifact(path: Path | None = None) -> dict[str, Any]:
    path = path or STATE_PATH
    base = empty_artifact()
    if not path.exists():
        return base
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return base
    if not isinstance(data, dict):
        return base
    base["runs"] = data.get("runs") if isinstance(data.get("runs"), dict) else {}
    if isinstance(data.get("job"), dict):
        job = empty_job()
        job.update({k: data["job"].get(k, job.get(k)) for k in job})
        # trim history
        hist = job.get("history") or []
        if isinstance(hist, list) and len(hist) > BOUNDS["max_history"]:
            job["history"] = hist[-BOUNDS["max_history"] :]
        base["job"] = job
    if isinstance(data.get("log"), list):
        base["log"] = data["log"][-BOUNDS["max_log_lines"] :]
    base["focus"] = data.get("focus")
    base["equity"] = data.get("equity")
    base["updated_at"] = data.get("updated_at")
    base["source"] = data.get("source")
    base["default"] = data.get("default") or DEFAULT_STRATEGY.name
    return base


def save_artifact(state: dict[str, Any], path: Path | None = None) -> Path:
    """Atomic write of viz_state.json with size / history caps."""
    path = path or STATE_PATH
    RESULTS.mkdir(parents=True, exist_ok=True)
    slim = dict(state)
    slim["bounds"] = BOUNDS
    slim["mode"] = "observe"
    slim["updated_at"] = time.time()
    slim["default"] = slim.get("default") or DEFAULT_STRATEGY.name
    # trim log + history
    if isinstance(slim.get("log"), list) and len(slim["log"]) > BOUNDS["max_log_lines"]:
        slim["log"] = slim["log"][-BOUNDS["max_log_lines"] :]
    job = slim.get("job")
    if isinstance(job, dict):
        hist = job.get("history") or []
        if isinstance(hist, list) and len(hist) > BOUNDS["max_history"]:
            job["history"] = hist[-BOUNDS["max_history"] :]
    runs = slim.get("runs")
    if isinstance(runs, dict):
        for stem, bucket in list(runs.items()):
            if not isinstance(bucket, dict):
                continue
            for suite in ("dual", "bulls", "corpus", "matrix"):
                if suite in bucket and isinstance(bucket[suite], dict):
                    bucket[suite] = _trim_suite(bucket[suite])

    raw = json.dumps(slim, indent=2)
    if len(raw.encode("utf-8")) > BOUNDS["max_state_bytes"]:
        # Emergency shrink: drop equity + truncate cells harder
        slim["equity"] = None
        if isinstance(slim.get("runs"), dict):
            for bucket in slim["runs"].values():
                if not isinstance(bucket, dict):
                    continue
                for suite in ("dual", "bulls", "corpus"):
                    r = bucket.get(suite)
                    if isinstance(r, dict) and isinstance(r.get("cells"), list):
                        r["cells"] = r["cells"][:40]
                        r["_truncated_cells"] = True
        raw = json.dumps(slim, indent=2)

    tmp = path.with_suffix(".tmp")
    tmp.write_text(raw, encoding="utf-8")
    # Windows often denies atomic replace while another reader holds the file.
    last_err: Exception | None = None
    for attempt in range(8):
        try:
            tmp.replace(path)
            last_err = None
            break
        except PermissionError as e:
            last_err = e
            time.sleep(0.05 * (attempt + 1))
    if last_err is not None:
        try:
            path.write_text(raw, encoding="utf-8")
            try:
                tmp.unlink(missing_ok=True)
            except OSError:
                pass
        except Exception:
            raise last_err from None
    return path


def _mutate(mutator: Callable[[dict[str, Any]], None], *, source: str = "agent") -> dict[str, Any]:
    with _pub_lock:
        state = load_artifact()
        mutator(state)
        state["source"] = source
        save_artifact(state)
        return state


def publish_log(text: str, cls: str = "", *, source: str = "agent") -> None:
    def mut(state: dict[str, Any]) -> None:
        log = state.setdefault("log", [])
        log.append({"t": time.time(), "text": text, "cls": cls})
        if len(log) > BOUNDS["max_log_lines"]:
            del log[: len(log) - BOUNDS["max_log_lines"]]

    _mutate(mut, source=source)


def publish_job_start(
    suite: str,
    strategy: str | Path,
    *,
    total: int | None = None,
    agent: str | None = None,
    source: str = "agent",
    trigger: str = "external",
) -> dict[str, Any]:
    stem = _stem_of(strategy)
    strat_name = Path(str(strategy)).name if str(strategy).endswith(".ms") else f"{stem}.ms"

    def mut(state: dict[str, Any]) -> None:
        job = empty_job()
        job.update(
            {
                "running": True,
                "suite": suite,
                "strategy": strat_name,
                "total": int(total or 0),
                "done": 0,
                "started_at": time.time(),
                "trigger": trigger,
                "source": source,
                "agent": agent,
                "locked": True,
                "lock_reason": f"{source} · {suite}",
                "remaining_n": int(total or 0),
            }
        )
        state["job"] = job
        bucket = state.setdefault("runs", {}).setdefault(stem, {})
        # Mark live for streaming — do NOT wipe prior completed cells/matrix.
        # Fresh cells replace by key via publish_cell; finished publish_run sets live=False.
        if suite != "matrix":
            prev = bucket.get(suite) if isinstance(bucket.get(suite), dict) else {}
            bucket[suite] = {
                **prev,
                "suite": suite,
                "strategy": strat_name,
                "n_total": int(total or prev.get("n_total") or 0),
                "live": True,
            }
        else:
            prev = bucket.get("matrix") if isinstance(bucket.get("matrix"), dict) else {}
            bucket["matrix"] = {
                **prev,
                "suite": "matrix",
                "strategy": strat_name,
                "total_cells": int(total or prev.get("total_cells") or 0),
                "n_total": int(total or prev.get("n_total") or 0),
                "live": True,
            }

    state = _mutate(mut, source=source)
    publish_log(f"> {suite} · {strat_name} [{source}{(' · ' + agent) if agent else ''}]", "hi", source=source)
    return state


def publish_cell(
    suite: str,
    strategy: str | Path,
    cell: dict[str, Any],
    *,
    done: int | None = None,
    total: int | None = None,
    n_pass: int | None = None,
    mean_d_sharpe: float | None = None,
    remaining: list[str] | None = None,
    remaining_n: int | None = None,
    current: dict[str, Any] | None = None,
    source: str = "agent",
) -> dict[str, Any]:
    stem = _stem_of(strategy)

    def mut(state: dict[str, Any]) -> None:
        job = state.setdefault("job", empty_job())
        job["running"] = True
        job["suite"] = suite
        job["strategy"] = Path(str(strategy)).name if str(strategy).endswith(".ms") else job.get("strategy")
        if done is not None:
            job["done"] = done
        if total is not None:
            job["total"] = total
        if n_pass is not None:
            job["n_pass"] = n_pass
        if mean_d_sharpe is not None:
            job["mean_d_sharpe"] = mean_d_sharpe
        if remaining is not None:
            job["remaining"] = remaining[:12]
        if remaining_n is not None:
            job["remaining_n"] = remaining_n
        elif remaining is not None:
            job["remaining_n"] = len(remaining)
        job["last_cell"] = cell
        job["current"] = current or {
            "symbol": cell.get("symbol") or cell.get("batch"),
            "window": cell.get("window"),
        }
        if not job.get("started_at"):
            job["started_at"] = time.time()
        _job_timing(job)
        hist = job.setdefault("history", [])
        hist.append(
            {
                "t": job["elapsed_s"],
                "done": job["done"],
                "n_pass": job.get("n_pass", 0),
                "mean_d_sharpe": job.get("mean_d_sharpe", 0.0),
            }
        )
        if len(hist) > BOUNDS["max_history"]:
            del hist[: len(hist) - BOUNDS["max_history"]]

        bucket = state.setdefault("runs", {}).setdefault(stem, {})
        if suite == "matrix":
            row = cell
            mtx = bucket.get("matrix") or {
                "suite": "matrix",
                "strategy": job.get("strategy"),
                "matrix": [],
                "perfect_cells": 0,
                "total_cells": job.get("total") or 0,
                "n_pass": 0,
                "n_total": job.get("total") or 0,
                "live": True,
            }
            mtx["matrix"] = [
                r
                for r in mtx.get("matrix", [])
                if not (
                    r.get("batch") == row.get("batch")
                    and r.get("window") == row.get("window")
                    and r.get("frequency") == row.get("frequency")
                )
            ]
            mtx["matrix"].append(row)
            mtx["perfect_cells"] = sum(1 for r in mtx["matrix"] if r.get("perfect"))
            mtx["n_pass"] = mtx["perfect_cells"]
            mtx["total_cells"] = job.get("total") or mtx.get("total_cells") or 0
            mtx["n_total"] = mtx["total_cells"]
            mtx["live"] = True
            bucket["matrix"] = mtx
            job["n_pass"] = mtx["perfect_cells"]
        else:
            partial = bucket.get(suite) or {
                "suite": suite,
                "strategy": job.get("strategy"),
                "n_pass": 0,
                "n_total": job.get("total") or 0,
                "pct": 0.0,
                "mean_d_sharpe": 0.0,
                "cells": [],
                "by_window": {},
                "live": True,
            }
            cells = [
                c
                for c in partial.get("cells", [])
                if not (c.get("window") == cell.get("window") and c.get("symbol") == cell.get("symbol"))
            ]
            cells.append(cell)
            if len(cells) > BOUNDS["max_cells_per_suite"]:
                cells = cells[-BOUNDS["max_cells_per_suite"] :]
            partial["cells"] = cells
            np_ = sum(1 for c in cells if c.get("pass"))
            dvals = [c["d_sharpe"] for c in cells if c.get("pass") and c.get("d_sharpe") is not None]
            partial["n_pass"] = np_
            partial["n_total"] = job.get("total") or partial.get("n_total") or len(cells)
            partial["pct"] = round(100.0 * np_ / max(len(cells), 1), 1)
            partial["mean_d_sharpe"] = round(sum(dvals) / len(dvals), 4) if dvals else 0.0
            partial["live"] = True
            bucket[suite] = partial
            job["n_pass"] = np_
            job["mean_d_sharpe"] = partial["mean_d_sharpe"]
            _ensure_promote(bucket)

        state["focus"] = {
            "stem": stem,
            "suite": suite,
            "symbol": (cell.get("symbol") or cell.get("batch")),
            "window": cell.get("window"),
        }

    return _mutate(mut, source=source)


def publish_run(
    suite: str,
    strategy: str | Path,
    result: dict[str, Any],
    *,
    source: str = "agent",
    agent: str | None = None,
) -> dict[str, Any]:
    """Publish a completed suite result (dual/bulls/corpus/matrix)."""
    stem = _stem_of(strategy)
    trimmed = _trim_suite(result)

    def mut(state: dict[str, Any]) -> None:
        bucket = state.setdefault("runs", {}).setdefault(stem, {})
        trimmed["live"] = False
        bucket[suite] = trimmed
        _ensure_promote(bucket)
        job = state.setdefault("job", empty_job())
        job["running"] = False
        job["suite"] = None
        job["current"] = None
        job["remaining"] = []
        job["remaining_n"] = 0
        job["locked"] = False
        job["lock_reason"] = None
        job["done"] = trimmed.get("n_total") or trimmed.get("total_cells") or job.get("done") or 0
        job["total"] = job["done"]
        job["n_pass"] = trimmed.get("n_pass") or trimmed.get("perfect_cells") or 0
        job["mean_d_sharpe"] = trimmed.get("mean_d_sharpe") or 0.0
        _job_timing(job)
        if agent:
            job["agent"] = agent

    state = _mutate(mut, source=source)
    n = trimmed.get("n_pass") if suite != "matrix" else trimmed.get("perfect_cells")
    tot = trimmed.get("n_total") if suite != "matrix" else trimmed.get("total_cells")
    publish_log(
        f"OK {suite} {n}/{tot} dBH={trimmed.get('mean_d_sharpe', 0):+.2f} ({trimmed.get('elapsed_s', '?')}s)",
        "ok",
        source=source,
    )
    return state


def publish_job_done(*, error: str | None = None, source: str = "agent") -> dict[str, Any]:
    def mut(state: dict[str, Any]) -> None:
        job = state.setdefault("job", empty_job())
        job["running"] = False
        job["locked"] = False
        job["lock_reason"] = None
        job["current"] = None
        job["remaining"] = []
        job["remaining_n"] = 0
        if error:
            job["error"] = error
        _job_timing(job)
        # clear live flags
        for bucket in (state.get("runs") or {}).values():
            if not isinstance(bucket, dict):
                continue
            for suite in ("dual", "bulls", "corpus", "matrix"):
                if isinstance(bucket.get(suite), dict):
                    bucket[suite]["live"] = False

    state = _mutate(mut, source=source)
    if error:
        publish_log(f"FAIL {error}", "bad", source=source)
    else:
        publish_log("job complete", "ok", source=source)
    return state


def publish_focus(stem: str, suite: str, symbol: str, window: str, *, source: str = "ui") -> dict[str, Any]:
    def mut(state: dict[str, Any]) -> None:
        state["focus"] = {"stem": stem, "suite": suite, "symbol": symbol, "window": window}

    return _mutate(mut, source=source)


def ingest_matrix_file(path: Path, *, source: str = "disk") -> dict[str, Any] | None:
    """Lift results/matrix_<stem>.json into viz_state runs bucket."""
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    stem = path.stem.replace("matrix_", "")
    matrix_rows = []
    for r in data.get("matrix") or []:
        summary = r.get("summary") or {}
        matrix_rows.append(
            {
                "batch": r.get("batch"),
                "window": r.get("window"),
                "honesty": r.get("honesty"),
                "frequency": r.get("frequency"),
                "n_pass": summary.get("n_pass"),
                "n_total": summary.get("n_symbols"),
                "perfect": summary.get("n_pass") == summary.get("n_symbols") and (summary.get("n_symbols") or 0) > 0,
                "mean_d_sharpe": summary.get("mean_d_sharpe"),
                "by_symbol": summary.get("by_symbol"),
            }
        )
    result = {
        "suite": "matrix",
        "strategy": data.get("strategy") or f"{stem}.ms",
        "path": data.get("strategy"),
        "n_pass": data.get("perfect_cells") or 0,
        "n_total": data.get("total_cells") or len(matrix_rows),
        "pct": round(100.0 * (data.get("coverage") or 0), 1),
        "perfect_cells": data.get("perfect_cells") or 0,
        "total_cells": data.get("total_cells") or len(matrix_rows),
        "matrix": matrix_rows,
        "elapsed_s": data.get("elapsed_s"),
    }
    return publish_run("matrix", stem, result, source=source)


def scan_result_artifacts() -> list[str]:
    """Ingest known matrix_*.json artifacts into viz_state (idempotent lift)."""
    lifted: list[str] = []
    if not RESULTS.exists():
        return lifted
    for path in sorted(RESULTS.glob("matrix_*.json")):
        if path.name.startswith("matrix_") and path.suffix == ".json":
            ingest_matrix_file(path, source="disk")
            lifted.append(path.name)
    return lifted


# ---------------------------------------------------------------------------
# Opt-in equity (never auto during suite)
# ---------------------------------------------------------------------------


def load_equity(
    strategy: str | Path,
    window: str,
    symbol: str,
    *,
    execution: str = "next-open",
    cost_bps: float = 10.0,
    source: str = "ui",
) -> dict[str, Any]:
    """One-cell equity via gene-runner --instrument. Opt-in only."""
    ensure_runner()
    strat = resolve_strategy(strategy)
    tape = FLAGSHIP / "tapes" / window / f"{symbol}.csv"
    if not tape.exists():
        return {"ok": False, "error": f"missing tape {window}/{symbol}.csv"}
    src = stitch_source(strat)
    with tempfile.NamedTemporaryFile("w", suffix=".ms", delete=False, encoding="utf-8") as tmp:
        tmp.write(src)
        src_path = Path(tmp.name)
    try:
        cmd = [
            "node",
            str(RUNNER),
            "--source",
            str(src_path),
            "--target",
            "js",
            "--tape",
            str(tape),
            "--execution",
            execution,
            "--cost-bps",
            str(cost_bps),
            "--instrument",
        ]
        try:
            proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "timeout"}
        lines = (proc.stdout or "").strip().splitlines()
        if not lines:
            return {"ok": False, "error": (proc.stderr or "no output")[:400]}
        try:
            data = json.loads(lines[-1])
        except json.JSONDecodeError:
            return {"ok": False, "error": lines[-1][:400]}
    finally:
        src_path.unlink(missing_ok=True)

    if not data.get("ok"):
        return {"ok": False, "error": str(data.get("error") or data)[:400]}

    eq = data.get("equity") or []
    if not isinstance(eq, list):
        eq = []
    # downsample
    max_pts = BOUNDS["equity_max_points"]
    if len(eq) > max_pts:
        step = max(1, len(eq) // max_pts)
        eq = eq[::step]
        if eq[-1] != (data.get("equity") or [None])[-1]:
            eq.append((data.get("equity") or [eq[-1]])[-1])

    start = float(eq[0]) if eq else 100_000.0
    if start <= 0:
        start = 100_000.0
    returns = [round((float(v) / start) - 1.0, 6) for v in eq]
    fills = data.get("fills") or []
    payload = {
        "ok": True,
        "strategy": strat.name,
        "stem": strat.stem,
        "window": window,
        "symbol": symbol,
        "bars": data.get("bars"),
        "trades": data.get("trades"),
        "sharpe": data.get("sharpe"),
        "max_drawdown": data.get("maxDrawdown"),
        "final_equity": data.get("finalEquity"),
        "equity": [round(float(v), 2) for v in eq],
        "returns": returns,
        "fill_n": len(fills) if isinstance(fills, list) else 0,
        "loaded_at": time.time(),
    }

    def mut(state: dict[str, Any]) -> None:
        state["equity"] = payload
        state["focus"] = {
            "stem": strat.stem,
            "suite": state.get("focus", {}).get("suite") if isinstance(state.get("focus"), dict) else None,
            "symbol": symbol,
            "window": window,
        }

    _mutate(mut, source=source)
    return payload


# ---------------------------------------------------------------------------
# Scoring loops (secondary — agents should prefer calling publish_* themselves)
# ---------------------------------------------------------------------------


def run_grid(
    strategy: Path,
    *,
    windows: list[str],
    symbols: list[str],
    suite: str,
    progress: ProgressCb | None = None,
    publish: bool = True,
    cancel: Callable[[], bool] | None = None,
) -> dict[str, Any]:
    """Score windows × symbols via warm batch-runner; publish cells as pairs complete."""
    ensure_runner()
    src = stitch_source(strategy)
    bh_src = buy_hold_source()
    cells: list[dict[str, Any]] = []
    n_pass = 0
    d_sum = 0.0
    d_n = 0
    total = len(windows) * len(symbols)
    done = 0
    t0 = time.time()
    plan = [(w, s) for w in windows for s in symbols]
    if publish:
        publish_job_start(suite, strategy.name, total=total, source="ui", trigger="ui")
    _emit(
        progress,
        {"type": "suite_start", "suite": suite, "strategy": strategy.name, "total": total},
    )

    jobs: list[dict[str, Any]] = []
    for win, sym in plan:
        tape = FLAGSHIP / "tapes" / win / f"{sym}.csv"
        jobs.append(
            {
                "id": f"{win}|{sym}|strat",
                "source": src,
                "tape": str(tape),
                "execution": "next-open",
                "costBps": 10,
            }
        )
        jobs.append(
            {
                "id": f"{win}|{sym}|bh",
                "source": bh_src,
                "tape": str(tape),
                "execution": "next-open",
                "costBps": 10,
            }
        )

    by_id: dict[str, Metrics] = {}
    flushed: set[str] = set()

    def flush_cell(win: str, sym: str) -> None:
        nonlocal done, n_pass, d_sum, d_n
        if cancel and cancel():
            raise RuntimeError("cancelled")
        key = f"{win}|{sym}"
        if key in flushed:
            return
        mk, bk = f"{win}|{sym}|strat", f"{win}|{sym}|bh"
        if mk not in by_id or bk not in by_id:
            return
        flushed.add(key)
        m, bh = by_id[mk], by_id[bk]
        # Rebuild score_one-equivalent cell without a second spawn.
        if not (FLAGSHIP / "tapes" / win / f"{sym}.csv").exists():
            cell = {
                "symbol": sym,
                "window": win,
                "ok": False,
                "pass": False,
                "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
                "error": "missing tape",
                "d_sharpe": None,
                "sharpe": None,
                "bh_sharpe": None,
                "trades": None,
                "ret": None,
                "mdd": None,
            }
        elif not m.ok:
            cell = {
                "symbol": sym,
                "window": win,
                "ok": False,
                "pass": False,
                "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
                "error": m.error or "run failed",
                "d_sharpe": None,
                "sharpe": None,
                "bh_sharpe": bh.sharpe if bh.ok else None,
                "trades": None,
                "ret": None,
                "mdd": None,
            }
        else:
            bh_sh = bh.sharpe if bh.ok else None
            d = (m.sharpe - bh_sh) if bh_sh is not None else None
            passed = cell_passes(m, bh_sh, True)
            cell = {
                "symbol": sym,
                "window": win,
                "ok": True,
                "pass": passed,
                "soft_wall": sym in SOFT_WALLS and win in BULL_WINDOWS,
                "error": None,
                "d_sharpe": round(d, 4) if d is not None else None,
                "sharpe": round(m.sharpe, 4),
                "bh_sharpe": round(bh_sh, 4) if bh_sh is not None else None,
                "trades": m.trades,
                "ret": round(m.total_return, 4),
                "mdd": round(m.max_drawdown, 4),
            }
        cells.append(cell)
        done += 1
        if cell["pass"]:
            n_pass += 1
            if cell["d_sharpe"] is not None:
                d_sum += cell["d_sharpe"]
                d_n += 1
        mean_dbh = round((d_sum / d_n) if d_n else 0.0, 4)
        remaining = [f"{s}@{w.replace('wf_', '').replace('eval_3m', 'eval')}" for w, s in plan[done:]]
        current = {"symbol": sym, "window": win}
        if publish:
            publish_cell(
                suite,
                strategy.name,
                cell,
                done=done,
                total=total,
                n_pass=n_pass,
                mean_d_sharpe=mean_dbh,
                remaining=remaining[:12],
                remaining_n=len(remaining),
                current=current,
                source="ui",
            )
        _emit(
            progress,
            {
                "type": "cell",
                "suite": suite,
                "strategy": strategy.name,
                "done": done,
                "total": total,
                "cell": cell,
                "n_pass": n_pass,
                "mean_d_sharpe": mean_dbh,
                "remaining": remaining[:12],
                "remaining_n": len(remaining),
            },
        )

    def on_result(jid: str, m: Metrics, _raw: dict[str, Any]) -> None:
        by_id[jid] = m
        parts = jid.split("|")
        if len(parts) == 3:
            flush_cell(parts[0], parts[1])

    try:
        run_gene_batch(jobs, on_result=on_result)
    except Exception:
        if publish:
            publish_job_done(error="batch failed", source="ui")
        raise

    mean_dbh = (d_sum / d_n) if d_n else 0.0
    result = {
        "suite": suite,
        "strategy": strategy.name,
        "path": str(strategy.relative_to(FLAGSHIP)).replace("\\", "/"),
        "n_pass": n_pass,
        "n_total": total,
        "pct": round(100.0 * n_pass / total, 1) if total else 0.0,
        "mean_d_sharpe": round(mean_dbh, 4),
        "elapsed_s": round(time.time() - t0, 2),
        "cells": cells,
        "by_window": {},
    }
    for win in windows:
        wcells = [c for c in cells if c["window"] == win]
        wp = sum(1 for c in wcells if c["pass"])
        result["by_window"][win] = {"n_pass": wp, "n_total": len(wcells)}
    if publish:
        publish_run(suite, strategy.name, result, source="ui")
    _emit(
        progress,
        {
            "type": "suite_done",
            "suite": suite,
            "strategy": strategy.name,
            "result": {k: v for k, v in result.items() if k != "cells"},
        },
    )
    return result


def run_dual(strategy: Path, progress: ProgressCb | None = None, **kw: Any) -> dict[str, Any]:
    return run_grid(strategy, windows=DUAL_WINDOWS, symbols=LIQUID10, suite="dual", progress=progress, **kw)


def run_bulls(strategy: Path, progress: ProgressCb | None = None, **kw: Any) -> dict[str, Any]:
    return run_grid(strategy, windows=BULL_WINDOWS, symbols=LIQUID10, suite="bulls", progress=progress, **kw)


def run_corpus(strategy: Path, progress: ProgressCb | None = None, **kw: Any) -> dict[str, Any]:
    return run_grid(
        strategy, windows=CORPUS_WINDOWS, symbols=AVAILABLE, suite="corpus", progress=progress, **kw
    )


def run_matrix_quick(
    strategy: Path,
    progress: ProgressCb | None = None,
    *,
    publish: bool = True,
    cancel: Callable[[], bool] | None = None,
) -> dict[str, Any]:
    """Reuse eval.cmd_matrix --quick logic inline for structured cells."""
    ensure_runner()
    src = stitch_source(strategy)
    batches = load_json(CONFIGS / "batches.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    frequencies = load_json(CONFIGS / "frequencies.json")

    batch_names = ["index3", "liquid10"]
    window_names = ["eval_3m", "wf_2022q1"]
    honesty_names = ["causal_realistic"]
    freq_names = ["any", "swing", "position"]

    matrix: list[dict[str, Any]] = []
    perfect = 0
    total = 0
    t0 = time.time()
    jobs = [
        (b, w, h, f)
        for b in batch_names
        for w in window_names
        for h in honesty_names
        for f in freq_names
    ]
    if publish:
        publish_job_start("matrix", strategy.name, total=len(jobs), source="ui", trigger="ui")
    _emit(
        progress,
        {"type": "suite_start", "suite": "matrix", "strategy": strategy.name, "total": len(jobs)},
    )
    for i, (b, w, h, f) in enumerate(jobs, 1):
        if cancel and cancel():
            raise RuntimeError("cancelled")
        remaining = [
            f"{bb}×{ww.replace('wf_', '').replace('eval_3m', 'eval')}×{ff}"
            for bb, ww, _hh, ff in jobs[i:]
        ]
        _emit(
            progress,
            {
                "type": "cell_start",
                "suite": "matrix",
                "strategy": strategy.name,
                "done": i - 1,
                "total": len(jobs),
                "symbol": f"{b}×{f}",
                "window": w,
                "remaining": remaining[:12],
                "remaining_n": len(remaining),
            },
        )
        total += 1
        cells = eval_batch(
            src,
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
        is_perfect = summary["n_pass"] == summary["n_symbols"] and summary["n_symbols"] > 0
        if is_perfect:
            perfect += 1
        row = {
            "batch": b,
            "window": w,
            "honesty": h,
            "frequency": f,
            "n_pass": summary["n_pass"],
            "n_total": summary["n_symbols"],
            "perfect": is_perfect,
            "mean_d_sharpe": round(summary["mean_d_sharpe"], 4),
            "by_symbol": summary["by_symbol"],
            "symbol": f"{b}×{f}",
            "pass": is_perfect,
            "d_sharpe": round(summary["mean_d_sharpe"], 4),
        }
        matrix.append(row)
        if publish:
            publish_cell(
                "matrix",
                strategy.name,
                row,
                done=i,
                total=len(jobs),
                n_pass=perfect,
                mean_d_sharpe=row["mean_d_sharpe"],
                remaining=remaining[:12],
                remaining_n=len(remaining),
                current={"symbol": f"{b}×{f}", "window": w},
                source="ui",
            )
        _emit(
            progress,
            {
                "type": "matrix_cell",
                "suite": "matrix",
                "strategy": strategy.name,
                "done": i,
                "total": len(jobs),
                "row": row,
                "remaining": remaining[:12],
                "remaining_n": len(remaining),
            },
        )

    result = {
        "suite": "matrix",
        "strategy": strategy.name,
        "path": str(strategy.relative_to(FLAGSHIP)).replace("\\", "/"),
        "n_pass": perfect,
        "n_total": total,
        "pct": round(100.0 * perfect / total, 1) if total else 0.0,
        "perfect_cells": perfect,
        "total_cells": total,
        "elapsed_s": round(time.time() - t0, 2),
        "matrix": matrix,
        "mean_d_sharpe": round(
            sum(r["mean_d_sharpe"] for r in matrix if r.get("mean_d_sharpe") is not None)
            / max(len([r for r in matrix if r.get("mean_d_sharpe") is not None]), 1),
            4,
        ),
    }
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / f"matrix_{strategy.stem}.json").write_text(
        json.dumps(
            {
                "strategy": result["path"],
                "perfect_cells": perfect,
                "total_cells": total,
                "coverage": perfect / total if total else 0.0,
                "matrix": [
                    {
                        "batch": r["batch"],
                        "window": r["window"],
                        "honesty": r["honesty"],
                        "frequency": r["frequency"],
                        "summary": {
                            "n_pass": r["n_pass"],
                            "n_symbols": r["n_total"],
                            "mean_d_sharpe": r["mean_d_sharpe"],
                            "by_symbol": r["by_symbol"],
                        },
                    }
                    for r in matrix
                ],
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    if publish:
        publish_run("matrix", strategy.name, result, source="ui")
    _emit(
        progress,
        {
            "type": "suite_done",
            "suite": "matrix",
            "strategy": strategy.name,
            "result": {k: v for k, v in result.items() if k != "matrix"},
        },
    )
    return result


def promote_status(dual: dict | None, bulls: dict | None, corpus: dict | None) -> dict[str, Any]:
    dual_ok = dual is not None and dual.get("n_pass", 0) >= PROMOTE["dual_min"]
    bulls_ok = bulls is not None and bulls.get("n_pass", 0) >= PROMOTE["bulls_min"]
    corpus_ok = corpus is not None and corpus.get("pct", 0) >= PROMOTE["corpus_pct_min"]
    dbh = dual.get("mean_d_sharpe") if dual else None
    dbh_ok = dbh is not None and dbh >= PROMOTE["dbh_floor"]
    cover_ok = bool(bulls_ok or corpus_ok)
    cleared = bool(dual_ok and cover_ok and dbh_ok)
    return {
        "cleared": cleared,
        "dual_ok": dual_ok,
        "bulls_ok": bulls_ok,
        "corpus_ok": corpus_ok,
        "dbh_ok": dbh_ok,
        "cover_ok": cover_ok,
        "thresholds": PROMOTE,
        "dual": (
            f"{dual.get('n_pass', 0)}/{dual.get('n_total', 0)}" if isinstance(dual, dict) else None
        ),
        "bulls": (
            f"{bulls.get('n_pass', 0)}/{bulls.get('n_total', 0)}" if isinstance(bulls, dict) else None
        ),
        "corpus": (
            f"{corpus.get('n_pass', 0)}/{corpus.get('n_total', 0)} ({corpus.get('pct', 0)}%)"
            if isinstance(corpus, dict)
            else None
        ),
        "dbh": dbh,
        "label": "PROMOTE CLEARED" if cleared else "BELOW PROMOTE BAR",
    }


def soft_wall_focus(bulls: dict | None) -> list[dict[str, Any]]:
    if not bulls:
        return []
    out = []
    for c in bulls.get("cells", []):
        if c.get("soft_wall"):
            out.append(c)
    return out


SUITES = {
    "dual": run_dual,
    "bulls": run_bulls,
    "corpus": run_corpus,
    "matrix": run_matrix_quick,
}


def run_suite(
    suite: str,
    strategy: Path,
    progress: ProgressCb | None = None,
    **kw: Any,
) -> dict[str, Any]:
    fn = SUITES.get(suite)
    if not fn:
        raise ValueError(f"unknown suite: {suite} (want {list(SUITES)})")
    return fn(strategy, progress=progress, **kw)
