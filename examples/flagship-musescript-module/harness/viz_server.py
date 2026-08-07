#!/usr/bin/env python3
"""Flagship grind OBSERVER — local dashboard over agent/CLI-published state.

Primary job: watch `results/viz_state.json` (and lift matrix_*.json) written by
external grinding agents / harness CLIs. In-app suite launch is secondary and
buried behind /api/run + an Advanced UI panel — single-flight, cancellable,
bounded.

Launch (from repo root):
  python examples/flagship-musescript-module/harness/viz_server.py
  # → http://127.0.0.1:8765/
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from eval import DEFAULT_STRATEGY, FLAGSHIP, RESULTS  # noqa: E402
from viz_core import (  # noqa: E402
    BOUNDS,
    STATE_PATH,
    empty_job,
    list_genomes,
    load_artifact,
    load_equity,
    publish_focus,
    publish_job_done,
    publish_log,
    resolve_strategy,
    run_suite,
    save_artifact,
    scan_result_artifacts,
)

STATIC = HERE / "viz_static"
PORT_DEFAULT = 8765

_lock = threading.RLock()
_subscribers: list[Any] = []
_job_cancel = threading.Event()
_observe_stop = threading.Event()
_observe_thread: threading.Thread | None = None
_ui_job_thread: threading.Thread | None = None

# In-memory mirror (also mirrored to disk by publish_* / save)
STATE: dict[str, Any] = {}


def _now() -> float:
    return time.time()


def _broadcast(payload: dict[str, Any]) -> None:
    raw = json.dumps(payload, default=str)
    dead = []
    with _lock:
        for q in _subscribers:
            try:
                q.append(raw)
            except Exception:
                dead.append(q)
        for q in dead:
            if q in _subscribers:
                _subscribers.remove(q)


def _snap() -> dict[str, Any]:
    """Build API state snapshot from artifact + live genome list."""
    art = load_artifact()
    art["genomes"] = list_genomes()
    art["default"] = DEFAULT_STRATEGY.name
    art["mode"] = "observe"
    art["bounds"] = BOUNDS
    art["state_path"] = str(STATE_PATH.relative_to(FLAGSHIP)).replace("\\", "/")
    # UI-local job lock flags (even when agent publishes)
    job = art.setdefault("job", empty_job())
    with _lock:
        if STATE.get("_ui_running"):
            job["locked"] = True
            job["lock_reason"] = job.get("lock_reason") or "ui run in flight"
    return art


def _push(event: str | None = None, extra: dict | None = None) -> None:
    msg: dict[str, Any] = {"type": "state", "state": _snap()}
    if event:
        msg["event"] = event
    if extra:
        msg.update(extra)
    _broadcast(msg)


def _observe_loop() -> None:
    """Poll viz_state.json mtime — agents publish; we fan out SSE."""
    last_mtime: float | None = None
    last_scan = 0.0
    while not _observe_stop.is_set():
        try:
            now = _now()
            # Periodically lift matrix_*.json artifacts (cheap)
            if now - last_scan > 8.0:
                scan_result_artifacts()
                last_scan = now
            if STATE_PATH.exists():
                mtime = STATE_PATH.stat().st_mtime
                if last_mtime is None or mtime != last_mtime:
                    last_mtime = mtime
                    _push("disk")
            else:
                if last_mtime is not None:
                    last_mtime = None
                    _push("disk_missing")
        except Exception as e:
            _broadcast({"type": "log", "text": f"observe error: {e}", "cls": "bad"})
        time.sleep(0.45)


def _ui_running() -> bool:
    with _lock:
        return bool(STATE.get("_ui_running"))


def start_ui_job(suite: str, strategy_ref: str, compare_ref: str | None = None) -> dict[str, Any]:
    """Secondary path — single-flight only. Prefer agents publishing externally."""
    with _lock:
        if STATE.get("_ui_running"):
            return {
                "ok": False,
                "error": "run locked — another in-app suite is already active (single-flight)",
                "locked": True,
            }
        # Also refuse if artifact says an external agent job is mid-flight
        art = load_artifact()
        job = art.get("job") or {}
        if job.get("running") and job.get("source") not in (None, "ui", "disk"):
            return {
                "ok": False,
                "error": f"run locked — external {job.get('source')} job in progress ({job.get('suite')})",
                "locked": True,
            }
        STATE["_ui_running"] = True
        _job_cancel.clear()

    strategy = resolve_strategy(strategy_ref)
    compare = resolve_strategy(compare_ref) if compare_ref else None
    suites = ["dual", "bulls", "corpus", "matrix"] if suite == "full" else [suite]

    def worker() -> None:
        try:
            targets = [(strategy, suites)]
            if compare is not None:
                targets.append((compare, suites))
            for strat, suite_list in targets:
                for s in suite_list:
                    if _job_cancel.is_set():
                        raise RuntimeError("cancelled")
                    publish_log(f"> UI {s} · {strat.name} [advanced]", "hi", source="ui")
                    run_suite(
                        s,
                        strat,
                        publish=True,
                        cancel=lambda: _job_cancel.is_set(),
                    )
            publish_job_done(source="ui")
        except Exception as e:
            publish_job_done(error=str(e), source="ui")
        finally:
            with _lock:
                STATE["_ui_running"] = False
            _job_cancel.clear()
            _push("job_done")

    global _ui_job_thread
    _ui_job_thread = threading.Thread(target=worker, daemon=True)
    _ui_job_thread.start()
    _push("job_start")
    return {"ok": True, "suite": suite, "strategy": strategy.name, "note": "advanced UI run — prefer agent publish"}


def stop_ui_job() -> None:
    _job_cancel.set()
    publish_log("cancel signal sent", "bad", source="ui")
    _push("cancel")


class Handler(BaseHTTPRequestHandler):
    server_version = "FlagshipObserve/2.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        if args and str(args[0]).startswith(("4", "5")):
            super().log_message(fmt, *args)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _json(self, code: int, obj: Any) -> None:
        raw = json.dumps(obj, default=str).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self._cors()
        self.end_headers()
        self.wfile.write(raw)

    def _bytes(self, code: int, data: bytes, ctype: str, *, cache: str = "no-store") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", cache)
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        if path in ("/", "/index.html"):
            html = (STATIC / "index.html").read_bytes()
            self._bytes(200, html, "text/html; charset=utf-8", cache="no-store, max-age=0")
            return
        if path == "/api/state":
            self._json(200, _snap())
            return
        if path == "/api/genomes":
            self._json(200, {"default": DEFAULT_STRATEGY.name, "genomes": list_genomes()})
            return
        if path == "/api/bounds":
            self._json(200, BOUNDS)
            return
        if path == "/api/equity":
            qs = parse_qs(parsed.query)
            strategy = (qs.get("strategy") or [None])[0]
            window = (qs.get("window") or [None])[0]
            symbol = (qs.get("symbol") or [None])[0]
            if not (strategy and window and symbol):
                self._json(400, {"ok": False, "error": "need strategy, window, symbol"})
                return
            # refuse if UI job mid-flight (equity is extra CPU)
            if _ui_running():
                self._json(409, {"ok": False, "error": "run locked — wait for suite to finish", "locked": True})
                return
            out = load_equity(strategy, window, symbol, source="ui")
            _push("equity")
            self._json(200 if out.get("ok") else 400, out)
            return
        if path == "/api/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self._cors()
            self.end_headers()
            q: list[str] = []
            with _lock:
                _subscribers.append(q)
            try:
                init = json.dumps({"type": "state", "state": _snap(), "event": "hello"}, default=str)
                self.wfile.write(f"data: {init}\n\n".encode("utf-8"))
                self.wfile.flush()
                while True:
                    if q:
                        item = q.pop(0)
                        self.wfile.write(f"data: {item}\n\n".encode("utf-8"))
                        self.wfile.flush()
                    else:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                        time.sleep(1.0)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass
            finally:
                with _lock:
                    if q in _subscribers:
                        _subscribers.remove(q)
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid json"})
            return

        # Agent publish passthrough (thin HTTP mirror of viz_core.publish_*)
        if path == "/api/publish":
            from viz_core import (  # noqa: WPS433
                publish_cell,
                publish_job_done,
                publish_job_start,
                publish_run,
            )

            kind = data.get("kind") or data.get("type")
            source = data.get("source") or "agent"
            try:
                if kind in ("job_start", "start"):
                    out = publish_job_start(
                        data["suite"],
                        data["strategy"],
                        total=data.get("total"),
                        agent=data.get("agent"),
                        source=source,
                        trigger=data.get("trigger") or "external",
                    )
                elif kind in ("cell", "publish_cell"):
                    out = publish_cell(
                        data["suite"],
                        data["strategy"],
                        data["cell"],
                        done=data.get("done"),
                        total=data.get("total"),
                        n_pass=data.get("n_pass"),
                        mean_d_sharpe=data.get("mean_d_sharpe"),
                        remaining=data.get("remaining"),
                        remaining_n=data.get("remaining_n"),
                        current=data.get("current"),
                        source=source,
                    )
                elif kind in ("run", "publish_run"):
                    out = publish_run(
                        data["suite"],
                        data["strategy"],
                        data["result"],
                        source=source,
                        agent=data.get("agent"),
                    )
                elif kind in ("done", "job_done"):
                    out = publish_job_done(error=data.get("error"), source=source)
                elif kind == "log":
                    publish_log(data.get("text") or "", cls=data.get("cls") or "", source=source)
                    out = load_artifact()
                else:
                    self._json(400, {"error": f"unknown publish kind: {kind}"})
                    return
                _push("publish")
                self._json(200, {"ok": True, "updated_at": out.get("updated_at")})
            except Exception as e:
                self._json(400, {"ok": False, "error": str(e)})
            return

        if path == "/api/focus":
            publish_focus(
                data.get("stem") or "",
                data.get("suite") or "dual",
                data.get("symbol") or "",
                data.get("window") or "",
                source="ui",
            )
            _push("focus")
            self._json(200, {"ok": True})
            return

        if path == "/api/equity":
            if _ui_running():
                self._json(409, {"ok": False, "error": "run locked", "locked": True})
                return
            out = load_equity(
                data.get("strategy") or str(DEFAULT_STRATEGY.relative_to(FLAGSHIP)).replace("\\", "/"),
                data["window"],
                data["symbol"],
                source="ui",
            )
            _push("equity")
            self._json(200 if out.get("ok") else 400, out)
            return

        if path == "/api/run":
            # Advanced / secondary — single-flight
            suite = data.get("suite") or "dual"
            strategy = data.get("strategy") or str(DEFAULT_STRATEGY.relative_to(FLAGSHIP)).replace("\\", "/")
            compare = data.get("compare")
            out = start_ui_job(suite, strategy, compare)
            self._json(200 if out.get("ok") else 409, out)
            return

        if path == "/api/stop":
            stop_ui_job()
            self._json(200, {"ok": True})
            return

        if path == "/api/scan":
            lifted = scan_result_artifacts()
            _push("scan")
            self._json(200, {"ok": True, "lifted": lifted})
            return

        self._json(404, {"error": "not found"})


def main() -> int:
    global _observe_thread
    ap = argparse.ArgumentParser(description="Flagship grind OBSERVER")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=PORT_DEFAULT)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)
    # Ensure artifact exists; lift any matrix jsons once
    if not STATE_PATH.exists():
        save_artifact(load_artifact())
    scan_result_artifacts()

    with _lock:
        STATE.clear()
        STATE["_ui_running"] = False

    _observe_stop.clear()
    _observe_thread = threading.Thread(target=_observe_loop, daemon=True)
    _observe_thread.start()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}/"
    print(f"Flagship OBSERVER -> {url}", flush=True)
    print(f"  watching {STATE_PATH.relative_to(FLAGSHIP)}", flush=True)
    print(f"  DEFAULT_STRATEGY = {DEFAULT_STRATEGY.name}", flush=True)
    print("  Agents: viz_core.publish_*  or  POST /api/publish", flush=True)
    print("  In-app suite launch is Advanced/secondary (single-flight).", flush=True)
    print("Ctrl+C to stop.", flush=True)
    if not args.no_open:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
    finally:
        httpd.server_close()
        _observe_stop.set()
        _job_cancel.set()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
