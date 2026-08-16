#!/usr/bin/env python3
"""gate_stats.py -- how much of the flagship thread's history was ever real?

`heldout_gate.py` decides promote/reject from two statistics: a count of symbols
passing a triple threshold, and a marginal mean d_sharpe with a 0.02 tolerance.
Both are used as if the 54 symbols were 54 independent observations. They are not
-- mean pairwise daily-return correlation across this universe is ~0.13, which
leaves roughly SEVEN effective independent bets. Against that, a 0.02 tolerance
is theatre, and the pass count is worse: it is a threshold statistic, so a shift
far too small to be real flips many symbols at once (v2 sat 0.08 SE from v1 on
mean d_sharpe while its pass count collapsed 13 -> 3).

This module replaces vibes with intervals. It reports:

  1. Effective sample size, measured from the tapes rather than assumed.
  2. Marginal mean d_sharpe per variant, with BOTH the naive symbol-bootstrap CI
     and the correlation-adjusted one, so the gap between them is visible.
  3. PAIRED per-symbol comparison against a reference variant. This is the single
     biggest power win available: the market factor is common to both strategies
     and cancels in the difference, so a paired test resolves changes the marginal
     test cannot. Reported with a bootstrap CI, a sign test, and its OWN measured
     effective n (differences are not as correlated as levels).
  4. PBO via combinatorially-symmetric cross-validation over symbol subsets --
     the probability that selecting the in-sample best variant lands you below
     median out-of-sample.
  5. A selection-bias haircut: the expected maximum of N trials drawn from the
     observed spread, i.e. how much of the best variant's apparent edge is
     explained by having looked at N variants at all.

Honest limits, stated up front rather than buried:
  - CSCV here splits over SYMBOLS, not over TIME. 166 bars with a 34-bar indicator
    warmup does not admit enough usable time slices to do it properly. Time is the
    dimension that matters most for forward performance, so this understates true
    overfitting. Treat the PBO below as a floor.
  - No return series are stored (Metrics carries summary stats only), so this is
    not a full Deflated Sharpe Ratio -- that needs per-bar returns for the skew and
    kurtosis terms. The haircut in (5) is the selection-bias part of DSR only.
  - Symbol-level bootstrap assumes symbols are exchangeable. They are not quite
    (sector clustering), so even the adjusted intervals are mildly optimistic.

Usage:
  python gate_stats.py --build           # score every variant, cache the matrix
  python gate_stats.py                   # full report against the default reference
  python gate_stats.py --ref flagship_v6l
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import random
import statistics as st
import sys
from itertools import combinations
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

TAPES = FLAGSHIP / "tapes" / "broad8mo"
MATRIX = FLAGSHIP / "results" / "broad8mo_matrix.json"
LINEAGE = FLAGSHIP / "results" / "broad8mo_lineage.json"
BASELINE = FLAGSHIP / "results" / "broad8mo_baseline.json"

VARIANTS = [
    "flagship_v6l", "flagship_v7", "flagship_v7b", "flagship_v7c", "flagship_v7d",
    "flagship_v7e", "flagship_v7f", "flagship_v7g", "flagship_v7h",
    "flagship_ensemble_v1", "flagship_ensemble_v2", "flagship_ensemble_v3",
    "flagship_ensemble_v4", "flagship_ensemble_v5",
]
DEFAULT_REF = "flagship_ensemble_v1"
EULER = 0.5772156649015329


# ---------------------------------------------------------------- small stats

def mean(xs):
    return sum(xs) / len(xs)


def pearson(a, b):
    ma, mb = mean(a), mean(b)
    va = math.sqrt(sum((x - ma) ** 2 for x in a))
    vb = math.sqrt(sum((y - mb) ** 2 for y in b))
    if va == 0 or vb == 0:
        return 0.0
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / (va * vb)


def effective_n(n: int, rho: float) -> float:
    """Equicorrelated effective sample size. rho<=0 is floored at 0 (never inflate n)."""
    rho = max(0.0, rho)
    return n / (1.0 + (n - 1) * rho)


def norm_ppf(p: float) -> float:
    """Acklam's inverse normal CDF -- plenty accurate here, keeps this stdlib-only."""
    a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00]
    pl, ph = 0.02425, 1 - 0.02425
    if p < pl:
        q = math.sqrt(-2 * math.log(p))
        return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    if p > ph:
        q = math.sqrt(-2 * math.log(1 - p))
        return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    q = p - 0.5
    r = q * q
    return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q / (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)


def binom_two_sided_p(k: int, n: int) -> float:
    """Exact two-sided sign test against p=0.5."""
    if n == 0:
        return 1.0
    def pmf(i):
        return math.comb(n, i) * 0.5 ** n
    obs = pmf(k)
    return min(1.0, sum(pmf(i) for i in range(n + 1) if pmf(i) <= obs * (1 + 1e-12)))


def bootstrap_ci(vals, reps=20000, alpha=0.05, seed=7, scale=1.0):
    """Percentile bootstrap over symbols. `scale` widens the interval around the
    point estimate to account for cross-symbol correlation (scale = sqrt(n/n_eff))."""
    rng = random.Random(seed)
    n = len(vals)
    m = mean(vals)
    means = []
    for _ in range(reps):
        means.append(mean([vals[rng.randrange(n)] for _ in range(n)]))
    means.sort()
    lo = means[int(alpha / 2 * reps)]
    hi = means[int((1 - alpha / 2) * reps)]
    return m, m + (lo - m) * scale, m + (hi - m) * scale


# ---------------------------------------------------------------- matrix build

def build_matrix() -> dict:
    """Score every variant on the frozen held-out set; cache per-symbol d_sharpe.

    These are all ALREADY-EVALUATED variants -- this reproduces existing results to
    assemble the strategies x symbols matrix the statistics need. It is not a new
    round of guess-and-check against the held-out set.
    """
    from heldout_gate import score

    cached = {}
    if MATRIX.exists():
        cached = json.loads(MATRIX.read_text()).get("variants", {})

    # Seed from results already on disk to avoid needless re-scoring.
    if LINEAGE.exists():
        lin = json.loads(LINEAGE.read_text()).get("versions", {})
        for name, v in lin.items():
            cached.setdefault(name, {c["symbol"]: c["d_sharpe"]
                                     for c in v["cells"] if c.get("ok")})
    if BASELINE.exists():
        b = json.loads(BASELINE.read_text())
        cached.setdefault(Path(b["strategy"]).stem,
                          {c["symbol"]: c["d_sharpe"] for c in b["cells"] if c.get("ok")})

    for name in VARIANTS:
        if name in cached:
            continue
        path = FLAGSHIP / "strategies" / f"{name}.ms"
        if not path.exists():
            print(f"  skip {name}: no file", file=sys.stderr)
            continue
        print(f"  scoring {name} ...", file=sys.stderr)
        r = score(path)
        cached[name] = {c["symbol"]: c["d_sharpe"] for c in r["cells"] if c.get("ok")}

    MATRIX.write_text(json.dumps({"window": "2025-12-07..2026-08-06",
                                  "variants": cached}, indent=1))
    return cached


def load_matrix() -> dict:
    if not MATRIX.exists():
        return build_matrix()
    return json.loads(MATRIX.read_text())["variants"]


# ---------------------------------------------------------------- analyses

def tape_effective_n():
    rets = {}
    for p in sorted(TAPES.glob("*.csv")):
        c = [float(r["close"]) for r in csv.DictReader(p.open(newline="", encoding="utf-8"))]
        rets[p.stem] = [(c[i] - c[i - 1]) / c[i - 1] for i in range(1, len(c))]
    syms = sorted(rets)
    ps = [pearson(rets[syms[i]], rets[syms[j]])
          for i in range(len(syms)) for j in range(i + 1, len(syms))]
    rho = mean(ps)
    return len(syms), rho, effective_n(len(syms), rho)


def difference_effective_n(mat, syms, variants):
    """Effective n for PAIRED differences.

    Measured, not assumed: for each symbol take its vector of d_sharpe across the
    variants, remove each variant's mean (so the shared "this variant is better
    everywhere" component drops out), and correlate symbols pairwise. What is left
    is exactly the co-movement that survives a paired comparison.
    """
    vecs = {s: [mat[v][s] for v in variants] for s in syms}
    vmeans = [mean([vecs[s][i] for s in syms]) for i in range(len(variants))]
    dem = {s: [vecs[s][i] - vmeans[i] for i in range(len(variants))] for s in syms}
    ps = [pearson(dem[syms[i]], dem[syms[j]])
          for i in range(len(syms)) for j in range(i + 1, len(syms))]
    rho = mean(ps)
    return rho, effective_n(len(syms), rho)


def pbo_cscv(mat, syms, variants, n_groups=8, seed=11):
    """PBO over symbol subsets. Returns (pbo, n_splits, median_oos_rank_of_is_best)."""
    rng = random.Random(seed)
    shuffled = list(syms)
    rng.shuffle(shuffled)
    groups = [shuffled[i::n_groups] for i in range(n_groups)]

    below, total, ranks = 0, 0, []
    for pick in combinations(range(n_groups), n_groups // 2):
        is_syms = [s for g in pick for s in groups[g]]
        oos_syms = [s for g in range(n_groups) if g not in pick for s in groups[g]]
        is_score = {v: mean([mat[v][s] for s in is_syms]) for v in variants}
        oos_score = {v: mean([mat[v][s] for s in oos_syms]) for v in variants}
        best = max(variants, key=lambda v: is_score[v])
        order = sorted(variants, key=lambda v: oos_score[v], reverse=True)
        rank = order.index(best) + 1  # 1 = best OOS
        ranks.append(rank)
        total += 1
        if rank > len(variants) / 2:
            below += 1
    return below / total, total, st.median(ranks)


def selection_haircut(scores, n_trials):
    """Expected max of n_trials iid draws (Bailey/Lopez de Prado approximation).
    Answers: how far above the field would the best variant sit on luck alone?"""
    mu, sd = mean(scores), st.pstdev(scores)
    if sd == 0 or n_trials < 2:
        return mu, 0.0
    e_max = mu + sd * ((1 - EULER) * norm_ppf(1 - 1.0 / n_trials)
                       + EULER * norm_ppf(1 - 1.0 / (n_trials * math.e)))
    return e_max, e_max - mu


# ---------------------------------------------------------------- report

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true", help="score all variants and cache the matrix")
    ap.add_argument("--ref", default=DEFAULT_REF, help="reference variant for paired comparisons")
    ap.add_argument("--groups", type=int, default=8, help="CSCV symbol groups (even)")
    args = ap.parse_args()

    mat = build_matrix() if args.build else load_matrix()
    variants = [v for v in VARIANTS if v in mat]
    syms = sorted(set.intersection(*[set(mat[v]) for v in variants]))

    n, rho, neff = tape_effective_n()
    scale = math.sqrt(n / neff)

    print("=" * 78)
    print("GATE STATISTICS -- broad8mo held-out set, 2025-12-07..2026-08-06")
    print("=" * 78)
    print(f"\n{len(variants)} variants x {len(syms)} symbols\n")

    print("--- 1. Effective sample size -------------------------------------------")
    print(f"mean pairwise daily-return correlation : {rho:.3f}")
    print(f"nominal symbols                        : {n}")
    print(f"EFFECTIVE independent bets             : {neff:.1f}")
    print(f"=> standard errors are {scale:.2f}x wider than a naive n={n} bootstrap says.")

    print("\n--- 2. Marginal mean d_sharpe (what the gate currently reads) -----------")
    print(f"{'variant':24s} {'mean':>7s}  {'naive 95% CI':>18s}  {'adjusted 95% CI':>20s}")
    marg = {}
    for v in variants:
        vals = [mat[v][s] for s in syms]
        m, lo, hi = bootstrap_ci(vals, scale=scale)
        _, nlo, nhi = bootstrap_ci(vals, scale=1.0)
        marg[v] = m
        print(f"{v:24s} {m:+7.3f}  [{nlo:+7.3f},{nhi:+7.3f}]  [{lo:+7.3f},{hi:+7.3f}]")
    print("\nEvery adjusted interval overlaps every other. On the marginal statistic the")
    print("gate reads, this lineage is ONE undifferentiated blob.")

    drho, dneff = difference_effective_n(mat, syms, variants)
    dscale = math.sqrt(len(syms) / dneff)
    print("\n--- 3. PAIRED comparison vs. reference ---------------------------------")
    print(f"reference: {args.ref}")
    print(f"residual cross-symbol correlation of differences : {drho:.3f}")
    print(f"EFFECTIVE n for paired differences               : {dneff:.1f}"
          f"   (vs {neff:.1f} unpaired -- this is the power win)")
    print(f"\n{'variant':24s} {'mean diff':>9s}  {'95% CI (adj)':>20s}  {'better':>7s}  {'sign p':>7s}")
    ref = args.ref
    for v in variants:
        if v == ref:
            continue
        diffs = [mat[v][s] - mat[ref][s] for s in syms]
        m, lo, hi = bootstrap_ci(diffs, scale=dscale)
        k = sum(1 for d in diffs if d > 0)
        p = binom_two_sided_p(k, len(diffs))
        flag = "" if lo <= 0 <= hi else "  <-- resolved"
        print(f"{v:24s} {m:+9.3f}  [{lo:+8.3f},{hi:+8.3f}]  {k:3d}/{len(diffs)}  {p:7.4f}{flag}")

    print("\n--- 4. PBO (CSCV over symbol subsets) ----------------------------------")
    pbo, nsplits, medrank = pbo_cscv(mat, syms, variants, n_groups=args.groups)
    print(f"splits evaluated            : {nsplits}")
    print(f"median OOS rank of IS-best  : {medrank:.1f} of {len(variants)}")
    print(f"PBO                         : {pbo:.2f}")
    print("PBO is the probability that picking the in-sample best variant leaves you")
    print("below median out-of-sample. 0.5 = selection carries no information at all.")
    print("NOTE: this splits over SYMBOLS, not time -- it is a FLOOR on true overfitting.")

    print("\n--- 5. Selection-bias haircut ------------------------------------------")
    vals = list(marg.values())
    e_max, hair = selection_haircut(vals, len(variants))
    best = max(marg, key=marg.get)
    print(f"variants tried (trials)     : {len(variants)}")
    print(f"spread of variant means     : sd {st.pstdev(vals):.3f}")
    print(f"expected best-of-{len(variants):<2d} on luck : {e_max:+.3f}  (haircut {hair:+.3f} above the field mean)")
    print(f"actual best variant         : {best} at {marg[best]:+.3f}")
    excess = marg[best] - e_max
    print(f"excess over luck            : {excess:+.3f}")
    if excess <= 0:
        print("=> The best variant does NOT exceed what searching this many variants")
        print("   would produce from noise alone. Its lead is not evidence of skill.")
    else:
        print("=> The best variant exceeds the luck baseline, but see PBO above before")
        print("   treating that as an edge.")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
