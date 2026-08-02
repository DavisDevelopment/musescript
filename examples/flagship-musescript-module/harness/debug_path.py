#!/usr/bin/env python3
"""Verify PathLatch persists inside a class strategy."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

SRC = """
class S extends FlagshipRisk {
  path = new PathLatch()
  function onBar() {
    when position() == 0 && path.get() != 0: path.clear()
    when position() == 0 && bar_index == 5: {
      path.set(2)
      long()
    }
    when path.is(2) && bars_in_trade >= 3: {
      path.clear()
      flat()
    }
  }
  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
"""


def main() -> int:
    tmp = ROOT / "examples/flagship-musescript-module/strategies/probes/_dbg_path.ms"
    tmp.write_text(SRC.strip() + "\n", encoding="utf-8")
    st = stitch_source(tmp)
    tape = ROOT / "examples/flagship-musescript-module/tapes/eval_3m/SPY.csv"
    m = run_gene(st, tape, execution="next-open", cost_bps=10)
    print("ok", m.ok, "trades", m.trades, "ret", m.total_return, "err", m.error)
    return 0 if m.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
