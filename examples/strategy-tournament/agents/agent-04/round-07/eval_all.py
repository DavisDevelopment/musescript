#!/usr/bin/env python3
"""Evaluate all round-07 strategies on crypto+FX causal harness."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
HARNESS = ROOT / "examples/strategy-tournament/harness/crypto_fx_lab.py"
ROUND = Path(__file__).resolve().parent


def main() -> int:
    rows: list[dict] = []
    for path in sorted(ROUND.glob("s0*.ms")):
        proc = subprocess.run(
            [sys.executable, str(HARNESS), "--eval", str(path)],
            cwd=str(ROOT), capture_output=True, text=True, check=True,
        )
        row = json.loads(proc.stdout)
        row["path"] = str(path.relative_to(ROOT)).replace("\\", "/")
        rows.append(row)
        out = ROUND / f"eval_{path.stem}.json"
        out.write_text(json.dumps(row, indent=2), encoding="utf-8")

    rows.sort(key=lambda r: r.get("score") or 0, reverse=True)
    summary = {
        "round": "round-07",
        "domain": "crypto+forex",
        "execution": "next-open",
        "rankings": [
            {
                "strategy": r["strategy"],
                "path": r["path"],
                "score": r.get("score"),
                "mean_sharpe": r.get("mean_sharpe"),
                "mean_d_sharpe": r.get("mean_d_sharpe"),
                "median_mdd": r.get("median_mdd"),
                "wf_mean_sharpe": r.get("wf_mean_sharpe"),
            }
            for r in rows
        ],
    }
    (ROUND / "_eval_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
