#!/usr/bin/env python3
import json
from pathlib import Path

RESULTS = Path(__file__).resolve().parents[1] / "results"
files = [
    "eval_flagship_v2_liquid10_eval_3m_causal_realistic_any.json",
    "eval_p_v2d_mutex_liquid10_eval_3m_causal_realistic_any.json",
    "eval_p_v2d_mutex_liquid10_wf_2022q1_causal_realistic_any.json",
    "eval_p_v2c_atr_primary_liquid10_eval_3m_causal_realistic_any.json",
]
for name in files:
    path = RESULTS / name
    if not path.exists():
        print("missing", name)
        continue
    d = json.loads(path.read_text(encoding="utf-8"))
    print("===", name, "===")
    print("keys:", list(d.keys())[:12])
    rows = d.get("rows") or d.get("results") or d.get("symbols") or d
    if isinstance(rows, dict):
        # maybe nested
        for k in ("by_symbol", "items", "evals"):
            if k in rows:
                rows = rows[k]
                break
    if isinstance(rows, list):
        for r in rows:
            sym = r.get("symbol") or r.get("sym")
            print(
                f"  {sym}: pass={r.get('pass', r.get('gate_pass', r.get('ok')))} "
                f"sharpe={r.get('sharpe')} d={r.get('d_sharpe', r.get('delta_sharpe'))} "
                f"tr={r.get('trades')} ret={r.get('total_return', r.get('ret'))}"
            )
    else:
        print(json.dumps(d, indent=2)[:1500])
