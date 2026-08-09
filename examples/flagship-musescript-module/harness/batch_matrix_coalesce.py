#!/usr/bin/env python3
"""OPEN_ITEMS 6.1c: mega-batch cmd_matrix vs per-slice spawn identity + spawn count.

Compares ``run_matrix_mega(coalesce=True)`` (one warm spawn) against the legacy
``coalesce=False`` path (one spawn per honesty×freq slice). Asserts exact
sharpe / MDD / trades / pass / freq_ok cell identity and reports spawn counts
+ wall times.

Usage (from repo root or harness/):
  python batch_matrix_coalesce.py           # quick honesty×freq smoke
  python batch_matrix_coalesce.py --full    # 2 honesty × 3 freqs (more slices)
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import (  # noqa: E402
    DEFAULT_STRATEGY,
    FLAGSHIP,
    TAPES,
    batch_spawn_count,
    build_tapes,
    load_json,
    reset_batch_spawn_count,
    run_matrix_mega,
    stitch_source,
    summarize,
)

CONFIGS = FLAGSHIP / "configs"


def _cell_key(c) -> tuple:
    m = c.metrics
    if not m.ok:
        return ("err", c.symbol, m.error, c.freq_ok, c.pass_cell)
    return (
        "ok",
        c.symbol,
        m.sharpe,
        m.max_drawdown,
        m.trades,
        c.bh_sharpe,
        c.d_sharpe,
        c.freq_ok,
        c.pass_cell,
    )


def _fingerprint(
    slices: list[tuple[str, str, str, str, list]],
) -> list[tuple]:
    rows: list[tuple] = []
    for b, w, h, f, cells in slices:
        summ = summarize(cells)
        rows.append(
            (
                b,
                w,
                h,
                f,
                summ["n_pass"],
                summ["n_symbols"],
                summ["score"],
                summ["mean_sharpe"],
                summ["mean_d_sharpe"],
                summ["mean_mdd"],
                tuple(_cell_key(c) for c in cells),
            )
        )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="6.1c matrix mega-batch identity smoke")
    ap.add_argument(
        "--full",
        action="store_true",
        help="Use 2 honesty × 3 freqs (more slices / larger spawn gap)",
    )
    ap.add_argument(
        "--strategy",
        type=Path,
        default=DEFAULT_STRATEGY,
        help="Strategy .ms (default flagship_v7h)",
    )
    args = ap.parse_args()

    batches = load_json(CONFIGS / "batches.json")
    windows = load_json(CONFIGS / "windows.json")
    honesty_cfg = load_json(CONFIGS / "honesty.json")
    frequencies = load_json(CONFIGS / "frequencies.json")
    if not (TAPES / "manifest.json").exists():
        print("tapes missing — building …")
        build_tapes(windows, batches)

    strategy = Path(args.strategy).resolve()
    source = stitch_source(strategy)

    # Small, honest smoke: 1 batch × 1 window × honesty × freqs.
    batch_names = ["index3"]
    window_names = ["eval_3m"]
    if args.full:
        honesty_names = ["causal_realistic", "causal_harsh"]
        freq_names = ["any", "swing", "position"]
    else:
        honesty_names = ["causal_realistic", "causal_harsh"]
        freq_names = ["any", "swing", "position"]

    slice_keys = [
        (b, w, h, f)
        for b in batch_names
        for w in window_names
        for h in honesty_names
        for f in freq_names
    ]
    n_slices = len(slice_keys)
    print(f"strategy={strategy.name}  slices={n_slices}  "
          f"(batches={batch_names} windows={window_names} "
          f"honesty={honesty_names} freqs={freq_names})")

    reset_batch_spawn_count()
    t0 = time.perf_counter()
    legacy = run_matrix_mega(
        source,
        slice_keys,
        batches=batches,
        honesty_cfg=honesty_cfg,
        frequencies=frequencies,
        coalesce=False,
    )
    legacy_wall = time.perf_counter() - t0
    legacy_spawns = batch_spawn_count()

    reset_batch_spawn_count()
    t1 = time.perf_counter()
    mega = run_matrix_mega(
        source,
        slice_keys,
        batches=batches,
        honesty_cfg=honesty_cfg,
        frequencies=frequencies,
        coalesce=True,
    )
    mega_wall = time.perf_counter() - t1
    mega_spawns = batch_spawn_count()

    fp_legacy = _fingerprint(legacy)
    fp_mega = _fingerprint(mega)
    if fp_legacy != fp_mega:
        print("IDENTITY FAIL — mega metrics differ from per-slice path", file=sys.stderr)
        for a, b in zip(fp_legacy, fp_mega):
            if a != b:
                print(f"  slice {a[:4]} != {b[:4]}", file=sys.stderr)
                print(f"    legacy={a[4:10]}", file=sys.stderr)
                print(f"    mega  ={b[4:10]}", file=sys.stderr)
                # Show first differing cell
                for i, (ca, cb) in enumerate(zip(a[10], b[10])):
                    if ca != cb:
                        print(f"    cell[{i}] legacy={ca}", file=sys.stderr)
                        print(f"    cell[{i}] mega  ={cb}", file=sys.stderr)
                        break
                break
        return 1

    if mega_spawns != 1:
        print(f"SPAWN FAIL — expected 1 mega spawn, got {mega_spawns}", file=sys.stderr)
        return 1
    if legacy_spawns != n_slices:
        print(
            f"SPAWN WARN — legacy expected {n_slices} spawns, got {legacy_spawns}",
            file=sys.stderr,
        )

    n_cells = sum(len(cells) for *_rest, cells in mega)
    print("IDENTITY OK — all slice summaries + cell metrics byte-identical")
    print(f"  cells checked: {n_cells} across {n_slices} honesty x freq slices")
    print(f"  legacy spawns: {legacy_spawns}  wall={legacy_wall:.2f}s")
    print(f"  mega   spawns: {mega_spawns}  wall={mega_wall:.2f}s")
    if legacy_wall > 0:
        print(f"  speedup: {legacy_wall / mega_wall:.1f}x wall (spawn coalesce)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
