#!/usr/bin/env python3
"""Evaluate round-07 strategies and write eval JSON + summary."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
ROUND = Path(__file__).resolve().parent
HARNESS = ROOT / "examples/strategy-tournament/harness/crypto_fx_lab.py"


def eval_strategy(path: Path) -> dict:
    proc = subprocess.run(
        [sys.executable, str(HARNESS), "--eval", str(path)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    return json.loads(proc.stdout)


def main() -> None:
    rows = []
    for i in range(1, 6):
        path = ROUND / f"s{i:02d}.ms"
        data = eval_strategy(path)
        out = ROUND / f"eval_s{i:02d}.json"
        out.write_text(json.dumps(data, indent=2), encoding="utf-8")
        rows.append(
            {
                "file": path.name,
                "score": data.get("score"),
                "mean_sharpe": data.get("mean_sharpe"),
                "mean_d_sharpe": data.get("mean_d_sharpe"),
                "median_mdd": data.get("median_mdd"),
                "wf_mean_sharpe": data.get("wf_mean_sharpe"),
                "per_symbol": {
                    sym: {
                        "sharpe": v.get("sharpe"),
                        "d_sharpe": v.get("d_sharpe"),
                        "trades": v.get("trades"),
                        "return": v.get("return"),
                    }
                    for sym, v in data.get("per_symbol", {}).items()
                },
            }
        )
        print(
            f"{path.name}: score={data.get('score'):.3f} "
            f"sharpe={data.get('mean_sharpe'):.3f} "
            f"d_sh={data.get('mean_d_sharpe'):.3f} "
            f"wf={data.get('wf_mean_sharpe'):.3f}"
        )
    (ROUND / "_eval_summary.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
