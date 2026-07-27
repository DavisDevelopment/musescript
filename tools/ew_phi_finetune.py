#!/usr/bin/env python3
"""Offline coordinate-descent finetune for EwPhiParams soft weights.

Reads feature export JSON from EwFinetuneExport / EwFinetuneCli, optimizes soft
tolerances and W2 retrace targets against a simple alignment loss, writes
finetuned_phi.json for EwPhiParams.loadFromJsonFile.

Loss (v1): maximize sum of soft_hit * sign(forward_return) * |forward_return|
when impulse/zigzag labels fire — rewards fib hits that precede aligned moves.

Hard impulse/corrective rule thresholds are NOT in the search space.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import random
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

# Soft-only keys eligible for finetune (never hard rule floors).
TUNABLE_SCALAR = [
    "fibHitTol",
    "timeHitTol",
    "equalityTol",
    "alternationWeight",
    "depthPriorFourthWeight",
    "equalityOneFiveWeight",
    "channelWeight",
    "w2Retrace_0",
    "w2Retrace_1",
    "w2Retrace_2",
    "w4Retrace_0",
    "w4Retrace_1",
    "w4Retrace_2",
]

BOUNDS: dict[str, tuple[float, float]] = {
    "fibHitTol": (0.03, 0.25),
    "timeHitTol": (0.15, 0.55),
    "equalityTol": (0.05, 0.30),
    "alternationWeight": (0.5, 2.0),
    "depthPriorFourthWeight": (0.5, 2.0),
    "equalityOneFiveWeight": (0.5, 2.0),
    "channelWeight": (0.3, 1.5),
    "w2Retrace_0": (0.35, 0.55),
    "w2Retrace_1": (0.55, 0.72),
    "w2Retrace_2": (0.72, 0.88),
    "w4Retrace_0": (0.18, 0.32),
    "w4Retrace_1": (0.32, 0.48),
    "w4Retrace_2": (0.42, 0.58),
}


def fib_ratio_hit(ratio: float, target: float, tol: float) -> float:
    """Mirror musescript SoftScores.fibRatio / equality."""
    if not math.isfinite(ratio) or not math.isfinite(target):
        return 0.0
    den = max(abs(ratio), abs(target))
    if den < 1e-12:
        return 1.0
    err = abs(ratio - target) / den
    if err <= tol:
        return 1.0
    soft = 1.0 - (err - tol) / (1.0 + tol)
    return max(0.0, soft)


def best_hit(ratio: float, targets: list[float], tol: float) -> float:
    if not math.isfinite(ratio) or ratio <= 0:
        return 0.0
    return max((fib_ratio_hit(ratio, t, tol) for t in targets), default=0.0)


def w2_targets(params: dict[str, float]) -> list[float]:
    return [params.get(f"w2Retrace_{i}", 0.618) for i in range(3)]


def w4_targets(params: dict[str, float]) -> list[float]:
    return [params.get(f"w4Retrace_{i}", 0.382) for i in range(3)]


def row_soft_score(row: dict[str, Any], params: dict[str, float]) -> float:
    tol = params.get("fibHitTol", 0.10)
    w2 = row.get("w2OverW1")
    w4 = row.get("w4OverW3")
    s = 0.0
    n = 0
    if isinstance(w2, (int, float)) and math.isfinite(w2):
        s += best_hit(float(w2), w2_targets(params), tol)
        n += 1
    if isinstance(w4, (int, float)) and math.isfinite(w4):
        s += best_hit(float(w4), w4_targets(params), tol)
        n += 1
    return s / n if n else 0.0


def alignment_loss(rows: list[dict[str, Any]], params: dict[str, float]) -> float:
    """Negative reward — minimize this."""
    total = 0.0
    weight = 0.0
    for row in rows:
        fwd = row.get("forwardReturn")
        if not isinstance(fwd, (int, float)) or not math.isfinite(fwd):
            continue
        label = str(row.get("hypLabel", ""))
        if label not in ("impulse5", "diagonal", "zigzag", "flat_regular", "flat_expanded"):
            continue
        soft = row_soft_score(row, params)
        sign = 1.0 if fwd >= 0 else -1.0
        total -= soft * sign * abs(fwd)
        weight += abs(fwd)
    if weight <= 0:
        return 0.0
    return total / weight


def coordinate_descent(
    base: dict[str, float],
    rows: list[dict[str, Any]],
    *,
    steps: int = 8,
    trials: int = 12,
    seed: int = 42,
) -> tuple[dict[str, float], float]:
    rng = random.Random(seed)
    best = copy.deepcopy(base)
    best_loss = alignment_loss(rows, best)
    keys = [k for k in TUNABLE_SCALAR if k in best]

    for _ in range(steps):
        improved = False
        for key in keys:
            lo, hi = BOUNDS.get(key, (best[key] * 0.85, best[key] * 1.15))
            local_best = best[key]
            local_loss = best_loss
            for _ in range(trials):
                cand = copy.deepcopy(best)
                cand[key] = lo + (hi - lo) * rng.random()
                loss = alignment_loss(rows, cand)
                if loss < local_loss:
                    local_loss = loss
                    local_best = cand[key]
            if local_loss < best_loss - 1e-9:
                best[key] = local_best
                best_loss = local_loss
                improved = True
        if not improved:
            break
    return best, best_loss


def load_features(path: Path) -> tuple[list[dict[str, Any]], dict[str, float]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("rows") or []
    meta = data.get("meta") or {}
    snapshot = meta.get("paramsSnapshot") or {}
    base = {k: float(v) for k, v in snapshot.items()}
    return rows, base


def main() -> None:
    ap = argparse.ArgumentParser(description="Finetune EwPhiParams from offline feature export")
    ap.add_argument("--in", dest="in_path", default=str(ROOT / "build" / "ew_finetune_features.json"))
    ap.add_argument("--out", dest="out_path", default=str(ROOT / "build" / "finetuned_phi.json"))
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--trials", type=int, default=12)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    in_path = Path(args.in_path)
    if not in_path.is_file():
        raise SystemExit(f"missing features: {in_path} (run ew-finetune export first)")

    rows, base = load_features(in_path)
    if not rows:
        raise SystemExit("no rows in feature export")

    base_loss = alignment_loss(rows, base)
    tuned, tuned_loss = coordinate_descent(
        base, rows, steps=args.steps, trials=args.trials, seed=args.seed
    )

    out_path = Path(args.out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(tuned, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"rows={len(rows)} base_loss={base_loss:.6f} tuned_loss={tuned_loss:.6f}")
    print(f"wrote {out_path}")
    delta = {k: tuned[k] for k in TUNABLE_SCALAR if k in tuned and abs(tuned[k] - base.get(k, 0)) > 1e-6}
    if delta:
        print("changed:", json.dumps(delta, indent=2))


if __name__ == "__main__":
    main()
