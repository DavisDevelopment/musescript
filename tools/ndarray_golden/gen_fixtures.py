#!/usr/bin/env python3
"""Generate numpy golden fixtures for MuseScript NdArray parity tests.

Usage (optional; numpy required only for regen):
  python tools/ndarray_golden/gen_fixtures.py

Writes JSON under tools/ndarray_golden/fixtures/. Committed goldens keep CI
hermetic without a hard numpy dependency on the Haxe/JS test path.
"""
from __future__ import annotations

import json
import os

try:
    import numpy as np
except ImportError as e:
    raise SystemExit("numpy required to regenerate fixtures: pip install numpy") from e

OUT = os.path.join(os.path.dirname(__file__), "fixtures")


def dump(name: str, payload: dict) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    print("wrote", path)


def main() -> None:
    a = np.arange(6.0).reshape(2, 3)
    col = np.array([[10.0], [20.0]])
    prod = a * col
    dump(
        "broadcast_mul_sum",
        {
            "a": a.reshape(-1).tolist(),
            "a_shape": list(a.shape),
            "col": col.reshape(-1).tolist(),
            "col_shape": list(col.shape),
            "prod": prod.reshape(-1).tolist(),
            "sum_axis1": prod.sum(axis=1).tolist(),
        },
    )
    x = np.array([1.0, 2.0, 3.0])
    y = np.array([4.0, 5.0, 6.0])
    dump(
        "dot_matmul",
        {
            "dot": float(np.dot(x, y)),
            "matmul_2x2": (np.array([[1.0, 2.0], [3.0, 4.0]]) @ np.array([[5.0, 6.0], [7.0, 8.0]]))
            .reshape(-1)
            .tolist(),
        },
    )

    # M2: transpose view + multi-axis reduce
    t = np.arange(24.0).reshape(2, 3, 4).transpose(1, 2, 0)
    dump(
        "transpose_sum_axes",
        {
            "shape": list(t.shape),
            "c_contiguous": bool(t.flags.c_contiguous),
            "sum_axes_0_2": t.sum(axis=(0, 2)).tolist(),
        },
    )

    cube = np.arange(1.0, 9.0).reshape(2, 2, 2)
    dump(
        "multi_axis_cube",
        {
            "sum_0_2": cube.sum(axis=(0, 2)).tolist(),
            "mean_all": float(cube.mean()),
            "std_axis1_row0": float(np.array([1.0, 2.0, 3.0, 4.0]).reshape(2, 2).std(axis=1, ddof=0)[0]),
        },
    )


if __name__ == "__main__":
    main()
