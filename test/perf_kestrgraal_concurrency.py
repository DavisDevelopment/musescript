"""Concurrency scaling benchmark for KestrGraal -- how much does wall-clock throughput improve
with N concurrent gRPC clients hammering the server vs. 1? This is the real lever for MuseGene's
population fitness loop (pop=200 independent backtests per generation): if per-thread Context
scaling holds, evaluating a generation in parallel across worker threads should beat evaluating it
serially by close to core-count, not just ~741k bars/sec x1.

Assumes a KestrGraal server is already running on 127.0.0.1:51117.

Run: .venv/Scripts/python test/perf_kestrgraal_concurrency.py
"""
from __future__ import annotations

import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "graal" / "src" / "main" / "python"))

import grpc  # noqa: E402
import kestrgraal_pb2 as pb  # noqa: E402
import kestrgraal_pb2_grpc as pb_grpc  # noqa: E402

BARS = 8419
N_CALLS = 200


def make_request() -> "pb.BacktestRequest":
    return pb.BacktestRequest(
        wasm_path="build/graal/on_bar.wasm",
        strings_path="build/graal/on_bar.strings.json",
        csv_path="data/real/spy.csv",
        params={"fast": 10.0, "slow": 30.0},
        preloaded=True,
    )


def run_calls(stub, n: int) -> None:
    req = make_request()
    for _ in range(n):
        reply = stub.Backtest(req)
        if reply.trades != 277:
            raise AssertionError(f"diverged: trades={reply.trades}")


def bench(n_workers: int, target: str) -> float:
    # One channel, N worker threads sharing it (grpc channels are thread-safe / support
    # concurrent RPCs -- this is the realistic client shape, not N separate channels).
    channel = grpc.insecure_channel(target)
    grpc.channel_ready_future(channel).result(timeout=5)
    stub = pb_grpc.KestrGraalStub(channel)

    # warm up
    run_calls(stub, 10)

    calls_per_worker = N_CALLS // n_workers
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=n_workers) as pool:
        futures = [pool.submit(run_calls, stub, calls_per_worker) for _ in range(n_workers)]
        for f in futures:
            f.result()
    elapsed = time.perf_counter() - t0
    total_calls = calls_per_worker * n_workers
    bars_per_sec = BARS * total_calls / elapsed
    print(
        f"workers={n_workers:2d}  {total_calls} calls in {elapsed:.3f}s  "
        f"({elapsed / total_calls * 1000:.3f} ms/call avg)  ~{bars_per_sec:,.0f} bars/sec aggregate"
    )
    channel.close()
    return bars_per_sec


def main() -> None:
    target = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1:51117"
    print(f"=== KestrGraal concurrency scaling ({N_CALLS} calls per config, preloaded mode) ===")
    results = {}
    for n_workers in (1, 2, 4, 8, 16):
        results[n_workers] = bench(n_workers, target)
    base = results[1]
    print("\n=== scaling summary (relative to 1 worker) ===")
    for n_workers, bps in results.items():
        print(f"  {n_workers:2d} workers: {bps / base:.2f}x")


if __name__ == "__main__":
    main()
