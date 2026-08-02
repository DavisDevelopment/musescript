#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
base = (
    ROOT / "examples/flagship-musescript-module/strategies/probes/p_v3_vol_split.ms"
).read_text(encoding="utf-8")


def main() -> int:
    for cut in [0.010, 0.012, 0.015, 0.018, 0.022]:
        src = base.replace("param calmCut: Scalar = 0.012", f"param calmCut: Scalar = {cut}")
        tmp = ROOT / "examples/flagship-musescript-module/strategies/probes/_tmp_vol.ms"
        tmp.write_text(src, encoding="utf-8")
        st = stitch_source(tmp)
        print("==== calmCut", cut, "====")
        for win in ["eval_3m", "wf_2022q1"]:
            npass = n = 0
            fails = []
            for sym in SYMS:
                tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
                m = run_gene(st, tape, execution="next-open", cost_bps=10)
                bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
                n += 1
                if not m.ok:
                    fails.append(sym + ":ERR")
                    continue
                d = m.sharpe - bh.sharpe
                ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
                if ok:
                    npass += 1
                else:
                    fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}")
            print(f"  {win}: {npass}/{n}  fails={fails}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
