"""Unit + perf test for the KestrGraal gRPC server (graal/KestrGraalServer.java).

Assumes a KestrGraal server is already running on 127.0.0.1:51117 (start it with
`mvn -q -B exec:java -Dexec.mainClass=musescript.graal.KestrGraalServer -Dexec.args="51117 .."`
from muse-script/graal/, or via run.ps1 once that's wired). Not a self-starting test —
this only proves the RPC contract and its numbers against the same known-good SPY
MA-cross result the M0 gate and the in-process graal stress harness already verified
(trades=277, finalEquity=725994.1667410003, sharpe=0.5795298962243104).

Run: .venv/Scripts/python test/test_kestrgraal.py [host:port]
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "graal" / "src" / "main" / "python"))

import grpc  # noqa: E402
import kestrgraal_pb2 as pb  # noqa: E402
import kestrgraal_pb2_grpc as pb_grpc  # noqa: E402

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
    for test in (test_ping, test_backtest_correctness, test_backtest_preloaded_matches_streaming):
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
