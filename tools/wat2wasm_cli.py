#!/usr/bin/env python3
"""Convert WAT → WASM using wasmtime (project venv)."""
from __future__ import annotations
import sys
from pathlib import Path

def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wat2wasm_cli.py in.wat out.wasm", file=sys.stderr)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    wat = src.read_text(encoding="utf-8")
    from wasmtime import wat2wasm
    data = wat2wasm(wat)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(bytes(data))
    print(f"wrote {dst} ({len(data)} bytes)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
