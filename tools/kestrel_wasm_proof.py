#!/usr/bin/env python3
"""Assemble and execute the Haxe-emitted Kestrel feature-tape proof."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from muse_math_runtime import load_strategy_module  # noqa: E402


def main() -> int:
    wat_path = ROOT / "build" / "kestrel" / "proof.wat"
    strings_path = ROOT / "build" / "kestrel" / "proof.strings.json"
    wat = wat_path.read_text(encoding="utf-8")
    strings = json.loads(strings_path.read_text(encoding="utf-8"))
    keys = [s.removeprefix("kestrel:") for s in strings if s.startswith("kestrel:")]

    calls = {"long": 0, "short": 0, "flat": 0}
    host = {
        "get_param": lambda _i: 0.0,
        "long": lambda _q: calls.__setitem__("long", calls["long"] + 1),
        "short": lambda _q: calls.__setitem__("short", calls["short"] + 1),
        "flat": lambda: calls.__setitem__("flat", calls["flat"] + 1),
    }
    mod = load_strategy_module(wat, host)
    bars = [
        {"open": 1.0, "high": 1.1, "low": 0.9, "close": 1.0, "volume": 10.0, "time": 0, "index": 0},
        {"open": 1.0, "high": 1.2, "low": 0.9, "close": 1.1, "volume": 11.0, "time": 1, "index": 1},
        {"open": 1.1, "high": 1.3, "low": 1.0, "close": 1.2, "volume": 12.0, "time": 2, "index": 2},
    ]
    keyed = {
        "graph:supply_chain:weighted_degree": [3.0, 3.0, 3.0],
        "tree:demo_tree:value": [1.0, 1.0, 1.0],
    }
    tapes = [keyed.get(k, [float("nan")] * len(bars)) for k in keys]
    mod.pack_and_configure(bars, tapes)
    for i in range(len(bars)):
        mod.on_bar(i)

    # Demo exits when either exitLong OR exitShort fires; at logic=1,
    # exitShort (logic > -0.1) is true, so each bar calls long then flat.
    if calls != {"long": 3, "short": 0, "flat": 3}:
        raise AssertionError(f"unexpected Kestrel feature-tape behavior: {calls}, keys={keys}")
    print(f"KESTREL_WASM_PROOF_OK features={len(keys)} calls={calls}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
