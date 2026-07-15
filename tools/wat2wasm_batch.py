#!/usr/bin/env python3
"""Assemble every .wat in a directory that lacks a matching .wasm (wasmtime)."""
from __future__ import annotations
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wat2wasm_batch.py dir", file=sys.stderr)
        return 2
    d = Path(sys.argv[1])
    from wasmtime import wat2wasm
    count = 0
    for wat in sorted(d.glob("*.wat")):
        out = wat.with_suffix(".wasm")
        if out.exists() and out.stat().st_mtime >= wat.stat().st_mtime:
            continue
        out.write_bytes(bytes(wat2wasm(wat.read_text(encoding="utf-8"))))
        count += 1
    print(f"assembled {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
