#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
SYMS = [
    "BTCUSD", "ETHUSD", "SOLUSD", "XRPUSD", "ADAUSD",
    "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD",
]


def eval_one(path: Path, symbol: str | None = None) -> dict:
    cmd = [
        sys.executable,
        str(ROOT / "examples/strategy-tournament/harness/crypto_fx_lab.py"),
        "--eval", str(path),
    ]
    if symbol:
        cmd += ["--symbol", symbol]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    return json.loads(proc.stdout)


def print_row(name: str, d: dict) -> None:
    print(
        f"{name:20} score={d.get('score', 0):7.3f} "
        f"sharpe={d.get('mean_sharpe') or 0:7.3f} "
        f"d_sh={d.get('mean_d_sharpe') or 0:7.3f} "
        f"mdd={d.get('median_mdd') or 0:.3f} "
        f"wf={d.get('wf_mean_sharpe') or 0:7.3f}"
    )


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "s01.ms"
    if len(sys.argv) > 2 and sys.argv[2] == "--symbols":
        for s in SYMS:
            d = eval_one(target, s)
            ps = d["per_symbol"][s]
            print(
                f"{s:8} trades={ps['trades']:2} sharpe={ps['sharpe']:7.3f} "
                f"d_sh={ps.get('d_sharpe') or 0:7.3f} ret={ps.get('return') or 0:7.3%}"
            )
    else:
        d = eval_one(target)
        print_row(target.name, d)
