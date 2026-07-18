"""Unit + perf test for the KestrGraal gRPC server (graal/KestrGraalServer.java).

Assumes a KestrGraal server is already running on 127.0.0.1:51117 (start it with
`mvn -q -B exec:java -Dexec.mainClass=musescript.graal.KestrGraalServer -Dexec.args="51117 .."`
from muse-script/graal/, or via run.ps1 once that's wired). Not a self-starting test —
this only proves the RPC contract and its numbers against the same known-good SPY
MA-cross result the M0 gate and the in-process graal stress harness already verified
(trades=277, finalEquity=725994.1667410003, sharpe=0.5795298962243104).

`test_corpus_parity` is the broader gate added 2026-07-18: the single pinned
MA-cross number above never exercised @on(position) or rising()/falling()'s
minBars form, so KestrGraal silently missed the get_position/get_entry_price/
get_bars_in_trade/get_cash/get_equity/get_unrealized_pnl host imports until a
real parity sweep against 8 corpus strategies over live SPY data caught it
(06_dual_ma_hard_stop failed outright with "env does not contain get_position").
This cross-validates against the JS tier (already proven bit-identical to
interp/wasm this session) on real strategies + a synthetic minBars/on_position
strategy, not just one pinned number.

Run: .venv/Scripts/python test/test_kestrgraal.py [host:port]
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "graal" / "src" / "main" / "python"))

import grpc  # noqa: E402
import kestrgraal_pb2 as pb  # noqa: E402
import kestrgraal_pb2_grpc as pb_grpc  # noqa: E402

GENE_RUNNER = ROOT / "build" / "js" / "gene-runner.js"
SPY_TAPE = ROOT / "data" / "real" / "spy.csv"
CORPUS_STRATEGIES = [
    "00_buy_hold", "01_golden_cross", "02_sma_cross_fast", "03_rsi_mean_rev",
    "04_rsi_dip_trend", "05_donchian", "06_dual_ma_hard_stop", "09_atr_squeeze",
]
# Exercises rising()/falling()'s minBars form (entry side is a no-op by design —
# bars_in_trade() is 0 pre-entry — so minBars is used on the exit/@on(position)
# side, which is its real, documented use) AND @on(position)/bars_in_trade()/
# unrealized_pnl() together — the two host-import gaps this test guards against.
MINBARS_ONPOSITION_SOURCE = '''
@strategy("minbars-onposition")
@param("fast", 10)
@param("slow", 30)
@on(bar) {
	f = sma(close, fast);
	s = sma(close, slow);
	if (position() == 0 && crossover(f, s)) long();
	if (position() != 0 && falling(close, 1, 3)) flat();
}
@on(position) {
	if (bars_in_trade() > 40 && unrealized_pnl() < 0) flat();
}
'''


def _run_node(args: list[str]) -> dict:
    r = subprocess.run(["node", str(GENE_RUNNER)] + args, cwd=str(ROOT),
                        capture_output=True, text=True, timeout=60)
    out = r.stdout.strip().splitlines()
    return json.loads(out[-1]) if out else {"ok": False, "error": r.stderr}


def _extract_params(source_path: Path) -> dict:
    d = _run_node(["--ast-json", "--source", str(source_path)])
    if not d.get("ok"):
        return {}
    out = {}
    for decl in d["program"]["decls"]:
        if decl.get("kind") == "paramDecl" and decl.get("def") is not None:
            v = decl["def"].get("value")
            if isinstance(v, (int, float)):
                out[decl["name"]] = float(v)
    return out


def _cross_validate(stub, name: str, source_path: Path = None, source_text: str = None, tmpdir: Path = None) -> tuple[bool, str]:
    if source_path is None:
        source_path = tmpdir / f"{name}.ms"
        source_path.write_text(source_text, encoding="utf-8")

    params = _extract_params(source_path)
    truth = _run_node(["--source", str(source_path), "--tape", str(SPY_TAPE), "--symbol", "SPY", "--target", "js"])
    wasm_path = tmpdir / f"{name}.wasm"
    r = _run_node(["--source", str(source_path), "--emit-wasm-file", str(wasm_path)])
    if not r.get("ok"):
        return True, f"SKIP (outside WASM subset): {r.get('reason')}"
    if not truth.get("ok"):
        return False, f"ground-truth JS run failed: {truth.get('error')}"

    req = pb.BacktestRequest(
        wasm_path=str(wasm_path),
        strings_path=str(wasm_path) + ".strings.json",
        csv_path=str(SPY_TAPE),
        params=params,
        preloaded=False,
    )
    reply = stub.Backtest(req, timeout=30)
    match = (
        reply.trades == truth.get("trades")
        and abs(reply.final_equity - truth.get("finalEquity", 0)) < 1e-3
        and abs(reply.sharpe - truth.get("sharpe", 0)) < 1e-6
    )
    detail = (f"js=({truth.get('trades')},{truth.get('finalEquity'):.2f},{truth.get('sharpe'):.4f}) "
              f"kestrgraal=({reply.trades},{reply.final_equity:.2f},{reply.sharpe:.4f})")
    return match, detail


def test_corpus_parity(stub: "pb_grpc.KestrGraalStub") -> None:
    import tempfile
    fails = []
    with tempfile.TemporaryDirectory() as td:
        tmpdir = Path(td)
        for name in CORPUS_STRATEGIES:
            src = ROOT / "corpus" / "strategies" / f"{name}.ms"
            ok, detail = _cross_validate(stub, name, source_path=src, tmpdir=tmpdir)
            print(f"{'PASS' if ok else 'FAIL'} test_corpus_parity[{name}]: {detail}")
            if not ok:
                fails.append(name)
        ok, detail = _cross_validate(stub, "minbars_onposition", source_text=MINBARS_ONPOSITION_SOURCE, tmpdir=tmpdir)
        print(f"{'PASS' if ok else 'FAIL'} test_corpus_parity[minbars_onposition]: {detail}")
        if not ok:
            fails.append("minbars_onposition")
    assert not fails, f"KestrGraal diverged from the JS tier on: {', '.join(fails)}"

EXPECTED_TRADES = 277
EXPECTED_EQUITY = 725994.1667410003
EXPECTED_SHARPE = 0.5795298962243104
EPS = 1e-6


def close(a: float, b: float, eps: float = EPS) -> bool:
    return abs(a - b) <= eps


def make_request() -> "pb.BacktestRequest":
    return pb.BacktestRequest(
        wasm_path="build/graal/on_bar.wasm",
        strings_path="build/graal/on_bar.strings.json",
        csv_path="data/real/spy.csv",
        params={"fast": 10.0, "slow": 30.0},
        preloaded=False,
    )


def test_ping(stub: "pb_grpc.KestrGraalStub") -> None:
    reply = stub.Ping(pb.PingRequest())
    assert reply.jvm_name, "ping: empty jvm_name"
    assert reply.uptime_ms >= 0, "ping: negative uptime"
    print(f"PASS test_ping: jvm={reply.jvm_name} {reply.jvm_version}  uptime_ms={reply.uptime_ms}")


def test_backtest_correctness(stub: "pb_grpc.KestrGraalStub") -> None:
    reply = stub.Backtest(make_request())
    ok = (
        reply.trades == EXPECTED_TRADES
        and close(reply.final_equity, EXPECTED_EQUITY)
        and close(reply.sharpe, EXPECTED_SHARPE)
    )
    print(
        f"{'PASS' if ok else 'FAIL'} test_backtest_correctness: "
        f"trades={reply.trades} finalEquity={reply.final_equity} sharpe={reply.sharpe} "
        f"elapsed_ms={reply.elapsed_ms:.3f}"
    )
    assert ok, (
        f"KestrGraal backtest diverged from the known-good SPY MA-cross result "
        f"(expected trades={EXPECTED_TRADES} equity={EXPECTED_EQUITY} sharpe={EXPECTED_SHARPE})"
    )


def test_backtest_preloaded_matches_streaming(stub: "pb_grpc.KestrGraalStub") -> None:
    req = make_request()
    req.preloaded = True
    reply = stub.Backtest(req)
    ok = (
        reply.trades == EXPECTED_TRADES
        and close(reply.final_equity, EXPECTED_EQUITY)
        and close(reply.sharpe, EXPECTED_SHARPE)
    )
    print(
        f"{'PASS' if ok else 'FAIL'} test_backtest_preloaded_matches_streaming: "
        f"trades={reply.trades} finalEquity={reply.final_equity} sharpe={reply.sharpe}"
    )
    assert ok, "preloaded-mode result diverged from streaming-mode / known-good result"


def perf_backtest_throughput(stub: "pb_grpc.KestrGraalStub", n: int = 50) -> None:
    req = make_request()
    # Warm up — first call(s) pay module-load + JIT warmup; not representative of steady state.
    for _ in range(5):
        stub.Backtest(req)

    t0 = time.perf_counter()
    for _ in range(n):
        reply = stub.Backtest(req)
        if reply.trades != EXPECTED_TRADES:
            raise AssertionError(f"perf run diverged mid-loop: trades={reply.trades}")
    elapsed = time.perf_counter() - t0

    bars = 8419  # data/real/spy.csv
    per_call_ms = elapsed / n * 1000
    bars_per_sec = bars * n / elapsed
    print(
        f"PERF test_backtest_throughput: {n} RPC calls in {elapsed:.3f}s "
        f"({per_call_ms:.3f} ms/call incl. gRPC round-trip, ~{bars_per_sec:,.0f} bars/sec)"
    )
    print(
        "  (in-process shared-Engine baseline was ~500k-900k bars/sec without RPC overhead -- "
        "this number honestly includes the network round-trip, it is not expected to match.)"
    )


def main() -> None:
    target = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:51117"
    channel = grpc.insecure_channel(target)
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
    except grpc.FutureTimeoutError:
        print(f"FAIL: could not connect to KestrGraal at {target} within 5s — is the server running?")
        sys.exit(1)

    stub = pb_grpc.KestrGraalStub(channel)

    failures = 0
    for test in (test_ping, test_backtest_correctness, test_backtest_preloaded_matches_streaming, test_corpus_parity):
        try:
            test(stub)
        except AssertionError as e:
            print(f"FAIL {test.__name__}: {e}")
            failures += 1

    if failures == 0:
        perf_backtest_throughput(stub)

    print(f"\n=== KestrGraal RPC test: {'PASS' if failures == 0 else 'FAIL'} ({failures} failure(s)) ===")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
