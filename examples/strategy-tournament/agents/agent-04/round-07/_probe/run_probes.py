#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
HARNESS = ROOT / "examples/strategy-tournament/harness/crypto_fx_lab.py"
PROBE = Path(__file__).resolve().parent

for p in sorted(PROBE.glob("p*.ms")):
    proc = subprocess.run(
        [sys.executable, str(HARNESS), "--eval", str(p)],
        cwd=str(ROOT), capture_output=True, text=True,
    )
    d = json.loads(proc.stdout)
    print(
        f"{p.stem}: score={d.get('score', 0):.3f} "
        f"sharpe={d.get('mean_sharpe') or 0:.3f} "
        f"dsh={d.get('mean_d_sharpe') or 0:.3f} "
        f"mdd={d.get('median_mdd') or 0:.3f} "
        f"wf={d.get('wf_mean_sharpe') or 0:.3f} "
        f"syms={d.get('symbols_tested', 0)}"
    )
