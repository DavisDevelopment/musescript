#!/usr/bin/env python3
"""OPEN_ITEMS 6.1a–b: cold run_gene vs warm run_gene_batch on top-9 meanrev.

Compares sharpe / maxDrawdown / trades / pass on the corpus grid
(AVAILABLE × WINDOWS), times the warm 9× corpus path (target ≪ 1 min).

Usage (from repo root or harness/):
  python batch_identity.py              # full top-9 identity + warm timing
  python batch_identity.py --warm-only  # 6.1b only
  python batch_identity.py --strat 1    # first N strategies (smoke)
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import Metrics, buy_hold_source, run_gene, run_gene_batch, stitch_source  # noqa: E402
from corpus_score import AVAILABLE, WINDOWS, _cell_ok  # noqa: E402

# Top 9 by score_probe pass rate (meanrev/README.md corpus scoreboard order).
TOP9 = [
    "rolling_zscore_vol_norm.ms",
    "turtle_soup_false_break.ms",
    "stoch_oversold.ms",
    "atr_band_reversion.ms",
    "cci_style.ms",
    "percent_rank_reversion.ms",
    "rsi14_neutral.ms",
    "zscore_sma20.ms",
    "bb_percentb.ms",
]

MEANREV = MOD / "strategies" / "meanrev"
EXEC = "next-open"
COST = 10.0
SEED = 42


def _tapes() -> list[tuple[str, str, Path]]:
    out: list[tuple[str, str, Path]] = []
    for win in WINDOWS:
        for sym in AVAILABLE:
            tape = MOD / "tapes" / win / f"{sym}.csv"
            if tape.exists():
                out.append((win, sym, tape))
    return out


def _pass(m: Metrics, bh: Metrics) -> bool:
    ok, _, _ = _cell_ok(m, bh)
    return ok


def _metrics_key(m: Metrics) -> tuple:
    """Identity tuple for regression asserts (exact floats + trades + ok)."""
    if not m.ok:
        return ("err", m.error)
    return ("ok", m.sharpe, m.max_drawdown, m.trades)


def build_jobs(strategies: list[Path], tapes: list[tuple[str, str, Path]]) -> list[dict]:
    bh_src = buy_hold_source()
    jobs: list[dict] = []
    # Shared buy-hold once per tape (source identical across strats).
    for win, sym, tape in tapes:
        jobs.append(
            {
                "id": f"bh|{win}|{sym}",
                "source": bh_src,
                "tape": str(tape),
                "execution": EXEC,
                "costBps": COST,
                "seed": SEED,
            }
        )
    for strat in strategies:
        st = stitch_source(strat)
        name = strat.name
        for win, sym, tape in tapes:
            jobs.append(
                {
                    "id": f"{name}|{win}|{sym}|strat",
                    "source": st,
                    "tape": str(tape),
                    "execution": EXEC,
                    "costBps": COST,
                    "seed": SEED,
                }
            )
    return jobs


def run_cold(
    strategies: list[Path],
    tapes: list[tuple[str, str, Path]],
) -> dict[str, Metrics]:
    """Per-cell cold gene-runner spawn (legacy path)."""
    bh_src = buy_hold_source()
    out: dict[str, Metrics] = {}
    n_bh = len(tapes)
    n_strat = len(strategies) * len(tapes)
    total = n_bh + n_strat
    done = 0
    t0 = time.perf_counter()

    for win, sym, tape in tapes:
        jid = f"bh|{win}|{sym}"
        out[jid] = run_gene(bh_src, tape, execution=EXEC, cost_bps=COST, timeout=120)
        done += 1
        if done % 20 == 0 or done == total:
            elapsed = time.perf_counter() - t0
            print(f"  cold {done}/{total} ({elapsed:.1f}s)", flush=True)

    for strat in strategies:
        st = stitch_source(strat)
        name = strat.name
        for win, sym, tape in tapes:
            jid = f"{name}|{win}|{sym}|strat"
            out[jid] = run_gene(st, tape, execution=EXEC, cost_bps=COST, timeout=120)
            done += 1
            if done % 20 == 0 or done == total:
                elapsed = time.perf_counter() - t0
                print(f"  cold {done}/{total} ({elapsed:.1f}s)", flush=True)
    return out


def compare(
    strategies: list[Path],
    tapes: list[tuple[str, str, Path]],
    cold: dict[str, Metrics],
    warm: dict[str, Metrics],
) -> list[str]:
    diffs: list[str] = []
    for win, sym, _tape in tapes:
        bh_c = cold.get(f"bh|{win}|{sym}", Metrics(ok=False, error="missing cold"))
        bh_w = warm.get(f"bh|{win}|{sym}", Metrics(ok=False, error="missing warm"))
        if _metrics_key(bh_c) != _metrics_key(bh_w):
            diffs.append(
                f"BH {win}|{sym}: cold={_metrics_key(bh_c)} warm={_metrics_key(bh_w)}"
            )

    for strat in strategies:
        name = strat.name
        for win, sym, _tape in tapes:
            jid = f"{name}|{win}|{sym}|strat"
            c = cold.get(jid, Metrics(ok=False, error="missing cold"))
            w = warm.get(jid, Metrics(ok=False, error="missing warm"))
            if _metrics_key(c) != _metrics_key(w):
                diffs.append(f"{jid}: cold={_metrics_key(c)} warm={_metrics_key(w)}")
                continue
            bh_c = cold[f"bh|{win}|{sym}"]
            bh_w = warm[f"bh|{win}|{sym}"]
            pc = _pass(c, bh_c)
            pw = _pass(w, bh_w)
            if pc != pw:
                diffs.append(f"{jid}: pass cold={pc} warm={pw}")
    return diffs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--warm-only", action="store_true", help="skip cold identity (6.1b only)")
    ap.add_argument("--strat", type=int, default=0, help="limit to first N strategies (0=all)")
    ap.add_argument(
        "--identity-windows",
        default="",
        help="comma subset of windows for cold identity (default: all); warm always full",
    )
    args = ap.parse_args()

    names = TOP9[: args.strat] if args.strat > 0 else list(TOP9)
    strategies = [MEANREV / n for n in names]
    for s in strategies:
        if not s.exists():
            print(f"missing strategy: {s}", file=sys.stderr)
            return 2

    tapes = _tapes()
    if not tapes:
        print("no corpus tapes found", file=sys.stderr)
        return 2

    id_wins = {w.strip() for w in args.identity_windows.split(",") if w.strip()}
    id_tapes = [t for t in tapes if t[0] in id_wins] if id_wins else tapes

    print(f"==== batch identity: {len(strategies)} strats x {len(tapes)} tapes ====")
    print(f"  strategies: {', '.join(n.name for n in strategies)}")
    print(f"  windows: {WINDOWS}")
    print(f"  symbols: {len(AVAILABLE)} available")
    if id_wins:
        print(f"  identity subset windows: {sorted(id_wins)} ({len(id_tapes)} tapes)")

    # --- 6.1b warm corpus timing (full grid always) ---
    warm_jobs = build_jobs(strategies, tapes)
    print(f"  warm jobs: {len(warm_jobs)} (incl. shared BH)", flush=True)
    t_warm0 = time.perf_counter()
    warm = run_gene_batch(
        warm_jobs,
        default_execution=EXEC,
        default_cost_bps=COST,
        seed=SEED,
        timeout=max(300, 5 * len(warm_jobs)),
    )
    warm_s = time.perf_counter() - t_warm0
    print(f"  WARM wall: {warm_s:.2f}s ({warm_s / 60.0:.2f} min) for {len(strategies)}x corpus")
    if warm_s < 60.0:
        print("  timing gate: PASS (well under 1 min)")
    else:
        print("  timing gate: FAIL (wanted well under 60s)")

    # Per-strategy corpus pass rates (warm) for sanity vs README.
    for strat in strategies:
        name = strat.name
        n_pass = n = 0
        for win, sym, _ in tapes:
            m = warm.get(f"{name}|{win}|{sym}|strat", Metrics(ok=False, error="missing"))
            bh = warm.get(f"bh|{win}|{sym}", Metrics(ok=False, error="missing"))
            n += 1
            n_pass += int(_pass(m, bh))
        print(f"  warm CORPUS {name}: {n_pass}/{n} ({100.0 * n_pass / n:.1f}%)")

    if args.warm_only:
        return 0 if warm_s < 60.0 else 1

    # --- 6.1a cold vs warm identity ---
    print(f"==== cold loop ({len(id_tapes)} tapes x {len(strategies)} strats + BH) ====", flush=True)
    t_cold0 = time.perf_counter()
    cold = run_cold(strategies, id_tapes)
    cold_s = time.perf_counter() - t_cold0
    print(f"  COLD wall: {cold_s:.2f}s ({cold_s / 60.0:.2f} min)")

    # Restrict warm dict view for identity tapes when subsetting.
    warm_id = warm
    if id_wins:
        keep = set()
        for win, sym, _ in id_tapes:
            keep.add(f"bh|{win}|{sym}")
            for strat in strategies:
                keep.add(f"{strat.name}|{win}|{sym}|strat")
        warm_id = {k: v for k, v in warm.items() if k in keep}

    diffs = compare(strategies, id_tapes, cold, warm_id)
    if diffs:
        print(f"==== IDENTITY FAIL ({len(diffs)} diffs) ====")
        for d in diffs[:40]:
            print(" ", d)
        if len(diffs) > 40:
            print(f"  … +{len(diffs) - 40} more")
        return 1

    n_cells = len(strategies) * len(id_tapes)
    print(f"==== IDENTITY PASS ({n_cells} strat cells + {len(id_tapes)} BH) ====")
    print(f"  sharpe/MDD/trades/pass exact match; warm {warm_s:.2f}s cold {cold_s:.2f}s")
    return 0 if warm_s < 60.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
