#!/usr/bin/env python3
"""heldout_v2.py -- scoring and inference on the multi-regime held-out set.

What this adds over `heldout_gate.py` (which scores ONE 8-month up-window):

  - 9 annual folds spanning genuinely different regimes (2014-2022), 300 symbols
    -> 2700 symbol-folds instead of 54 symbols.
  - A per-fold regime table. On broad8mo the regime effect measured ~7x the
    variant effect (spread 1.090 vs 0.256), so per-fold results are the signal
    and the pooled number is the summary, not the other way round.
  - PBO over TIME. broad8mo could only do CSCV over symbols, which is blind to
    the exact overfitting the lineage suffers from. Folds are the split unit here.
  - A sealed set (2023-01-28 -> 2026-08, strictly later than every working fold)
    that this script REFUSES to score unless you pass --unseal-final-answer.

Usage:
  python harness/heldout_v2.py strategies/flagship_ensemble_v1.ms --set-baseline
  python harness/heldout_v2.py strategies/flagship_ensemble_v4.ms
  python harness/heldout_v2.py --all-variants        # build the full matrix
  python harness/heldout_v2.py --report              # inference over the matrix
"""
from __future__ import annotations

import argparse
import json
import math
import random
import statistics as st
import sys
from itertools import combinations
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene_batch, stitch_source, buy_hold_source  # noqa: E402
from gate_stats import VARIANTS, bootstrap_ci, effective_n, pearson, binom_two_sided_p  # noqa: E402

TAPES = FLAGSHIP / "tapes" / "heldout_v2"
MANIFEST = TAPES / "manifest.json"
MATRIX = FLAGSHIP / "results" / "heldout_v2_matrix.json"
BHCACHE = FLAGSHIP / "results" / "heldout_v2_bh.json"
BASELINE = FLAGSHIP / "results" / "heldout_v2_baseline.json"


def manifest() -> dict:
    if not MANIFEST.exists():
        print("no heldout_v2 set. Build it first:\n"
              "  python harness/build_heldout_v2.py --sealed", file=sys.stderr)
        raise SystemExit(2)
    return json.loads(MANIFEST.read_text())


def folds(sealed: bool = False) -> list[str]:
    m = manifest()
    return sorted((m["sealed_folds"] if sealed else m["working_folds"]).keys())


def _bh_cache(fold_names: list[str]) -> dict:
    cache = json.loads(BHCACHE.read_text()) if BHCACHE.exists() else {}
    src = buy_hold_source()
    dirty = False
    for f in fold_names:
        if f in cache:
            continue
        d = TAPES / f
        syms = sorted(p.stem for p in d.glob("*.csv"))
        jobs = [{"id": s, "source": src, "tape": str(d / f"{s}.csv"),
                 "execution": "next-open", "costBps": 10} for s in syms]
        print(f"  buy-hold {f} ({len(jobs)}) ...", file=sys.stderr)
        res = run_gene_batch(jobs)
        cache[f] = {s: {"sharpe": r.sharpe, "ret": r.total_return}
                    for s, r in res.items() if r.ok}
        dirty = True
    if dirty:
        BHCACHE.write_text(json.dumps(cache))
    return cache


def score(path: Path, fold_names: list[str]) -> dict:
    """Per-fold, per-symbol d_sharpe for one strategy."""
    bh = _bh_cache(fold_names)
    src = stitch_source(path)
    out = {}
    for f in fold_names:
        d = TAPES / f
        syms = sorted(p.stem for p in d.glob("*.csv"))
        jobs = [{"id": s, "source": src, "tape": str(d / f"{s}.csv"),
                 "execution": "next-open", "costBps": 10} for s in syms]
        res = run_gene_batch(jobs)
        cell = {}
        for s, r in res.items():
            if not r.ok or s not in bh[f]:
                continue
            cell[s] = {"d": round(r.sharpe - bh[f][s]["sharpe"], 4),
                       "sharpe": round(r.sharpe, 4),
                       "trades": r.trades,
                       "dd": round(r.max_drawdown, 4)}
        out[f] = cell
        ds = [c["d"] for c in cell.values()]
        print(f"  {f}: n={len(ds):3d}  mean d_sharpe {st.mean(ds):+.3f}", file=sys.stderr)
    return out


# ---------------------------------------------------------------- inference

def pooled_pairs(mat, ref, var, fold_names):
    """Paired per-(symbol,fold) differences vs the reference variant."""
    out = []
    for f in fold_names:
        a, b = mat[var].get(f, {}), mat[ref].get(f, {})
        for s in set(a) & set(b):
            out.append(a[s]["d"] - b[s]["d"])
    return out


def within_fold_rho(mat, var, fold_names):
    """Cross-symbol correlation of d_sharpe WITHIN folds, estimated across folds.
    Symbols are the unit; each fold gives one observation per symbol."""
    syms = sorted(set.intersection(*[set(mat[var][f]) for f in fold_names]))
    vecs = {s: [mat[var][f][s]["d"] for f in fold_names] for s in syms}
    fmeans = [st.mean([vecs[s][i] for s in syms]) for i in range(len(fold_names))]
    dem = {s: [vecs[s][i] - fmeans[i] for i in range(len(fold_names))] for s in syms}
    sample = syms if len(syms) <= 120 else random.Random(3).sample(syms, 120)
    ps = [pearson(dem[a], dem[b])
          for i, a in enumerate(sample) for b in sample[i + 1:]]
    return st.mean(ps) if ps else 0.0


def time_pbo(mat, variants, fold_names, n_is=4):
    """PBO with FOLDS as the split unit -- overfitting across time, which is the
    dimension broad8mo's symbol-CSCV could not touch."""
    below, total, ranks = 0, 0, []
    for pick in combinations(range(len(fold_names)), n_is):
        is_f = [fold_names[i] for i in pick]
        oos_f = [f for i, f in enumerate(fold_names) if i not in pick]
        def m(v, fs):
            vals = [c["d"] for f in fs for c in mat[v][f].values()]
            return st.mean(vals) if vals else float("-inf")
        best = max(variants, key=lambda v: m(v, is_f))
        order = sorted(variants, key=lambda v: m(v, oos_f), reverse=True)
        r = order.index(best) + 1
        ranks.append(r)
        total += 1
        if r > len(variants) / 2:
            below += 1
    return below / total, total, st.median(ranks)


def report(ref: str) -> int:
    if not MATRIX.exists():
        print("no matrix yet -- run with --all-variants", file=sys.stderr)
        return 2
    mat = json.loads(MATRIX.read_text())
    fold_names = folds()
    variants = [v for v in VARIANTS if v in mat]
    m = manifest()

    print("=" * 84)
    print("HELD-OUT v2 -- 9 annual regime folds, "
          f"{m['universe_size']} symbols  ({len(variants)} variants)")
    print("=" * 84)

    print("\n--- Per-fold mean d_sharpe (the regime table) --------------------------")
    hdr = "".join(f"{f[-4:]:>8s}" for f in fold_names)
    print(f"{'variant':24s}{hdr}{'pooled':>9s}")
    pooled = {}
    for v in variants:
        cells, row = [], ""
        for f in fold_names:
            ds = [c["d"] for c in mat[v][f].values()]
            cells += ds
            row += f"{st.mean(ds):+8.2f}"
        pooled[v] = st.mean(cells)
        print(f"{v:24s}{row}{pooled[v]:+9.3f}")
    print("\nregime notes: " + ", ".join(
        f"{f[-4:]}={m['working_folds'][f]['regime'].split(',')[0]}" for f in fold_names))

    fmeans = {f: st.mean([c["d"] for v in variants for c in mat[v][f].values()])
              for f in fold_names}
    vmeans = pooled
    print(f"\nspread ACROSS FOLDS   : {max(fmeans.values()) - min(fmeans.values()):.3f}"
          f"   (sd {st.pstdev(list(fmeans.values())):.3f})")
    print(f"spread ACROSS VARIANTS: {max(vmeans.values()) - min(vmeans.values()):.3f}"
          f"   (sd {st.pstdev(list(vmeans.values())):.3f})")

    print(f"\n--- Paired vs {ref} ---------------------------")
    rho = within_fold_rho(mat, ref, fold_names)
    print(f"{'variant':24s} {'paired d':>9s}  {'95% CI':>20s}  {'better':>11s} {'sign p':>8s}")
    for v in variants:
        if v == ref:
            continue
        diffs = pooled_pairs(mat, ref, v, fold_names)
        if not diffs:
            continue
        mu, lo, hi = bootstrap_ci(diffs, reps=4000)
        k = sum(1 for d in diffs if d > 0)
        n = len(diffs)
        if n < 1200:
            p = binom_two_sided_p(k, n)
        else:
            # Normal approximation with continuity correction. (An earlier version
            # printed a crude 3-sigma 0/1 flag in this column and labelled it "sign p"
            # -- it reported p=1.0000 for a genuinely significant 1411/2700. Fixed.)
            z = (abs(k - n / 2) - 0.5) / math.sqrt(n * 0.25)
            p = math.erfc(z / math.sqrt(2))
        flag = "" if lo <= 0 <= hi else "  <-- RESOLVED"
        print(f"{v:24s} {mu:+9.3f}  [{lo:+8.3f},{hi:+8.3f}]  {k:5d}/{len(diffs):<5d} {p:8.4f}{flag}")
    print(f"\n(within-fold cross-symbol correlation of d_sharpe: {rho:.3f} -> "
          f"~{effective_n(m['universe_size'], rho):.0f} effective bets per fold, "
          f"x{len(fold_names)} folds)")

    print("\n--- PBO over TIME (folds as the split unit) ----------------------------")
    pbo, n, med = time_pbo(mat, variants, fold_names)
    print(f"splits: {n}   median OOS rank of IS-best: {med:.1f} of {len(variants)}   PBO: {pbo:.2f}")
    print("This is the test broad8mo structurally could not run. PBO near 0.5 means")
    print("picking the best variant on some regimes tells you nothing about others.")
    print()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("strategy", nargs="?")
    ap.add_argument("--all-variants", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--set-baseline", action="store_true")
    ap.add_argument("--ref", default="flagship_ensemble_v1")
    ap.add_argument("--unseal-final-answer", action="store_true",
                    help="score the SEALED 2023-2026 folds. One-way door: every look "
                         "costs a multiple-testing haircut and cannot be undone.")
    args = ap.parse_args()

    fold_names = folds(sealed=args.unseal_final_answer)
    if args.unseal_final_answer:
        print("!" * 78, file=sys.stderr)
        print("UNSEALING the held-out test set. Record this in BROAD8MO_REPORT.md with the",
              file=sys.stderr)
        print("date, the candidate, and why. It is no longer sealed after this run.",
              file=sys.stderr)
        print("!" * 78, file=sys.stderr)

    if args.report:
        return report(args.ref)

    mat = json.loads(MATRIX.read_text()) if MATRIX.exists() else {}
    todo = VARIANTS if args.all_variants else ([Path(args.strategy).stem] if args.strategy else [])
    if not todo:
        return report(args.ref)

    for name in todo:
        if name in mat and not args.strategy:
            continue
        p = FLAGSHIP / "strategies" / f"{name}.ms"
        if not p.exists():
            print(f"skip {name}: no file", file=sys.stderr)
            continue
        print(f"scoring {name}", file=sys.stderr)
        mat[name] = score(p, fold_names)
        MATRIX.write_text(json.dumps(mat))

    if args.set_baseline and args.strategy:
        BASELINE.write_text(json.dumps({"strategy": Path(args.strategy).stem}))
        print(f"baseline set: {Path(args.strategy).stem}", file=sys.stderr)
    return report(args.ref)


if __name__ == "__main__":
    raise SystemExit(main())
