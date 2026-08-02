#!/usr/bin/env python3
"""Ceiling ensemble — oracle pick best sleeve per symbol (research only).

Runs flagship_v4 + isolated edge sleeves, picks the max pass / d_sharpe book
per (window, symbol), and mines simple tape features that predict the winner
so v5 can encode a router without looking ahead.

  python examples/flagship-musescript-module/harness/ceiling_ensemble.py
"""

from __future__ import annotations

import csv
import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FLAGSHIP = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import RESULTS, Metrics, buy_hold_source, rel, run_gene, stitch_source  # noqa: E402

SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
WINDOWS = ["eval_3m", "wf_2022q1"]

# name -> (path relative to flagship OR None for inline), stitch?
SLEEVES: dict[str, Path] = {
    "v4": FLAGSHIP / "strategies" / "flagship_v4.ms",
    "iwm_seed": FLAGSHIP / "strategies" / "sleeves" / "iwm_seed.ms",
    "atr_only": FLAGSHIP / "strategies" / "sleeves" / "atr_only.ms",
    "macd_one_shot": FLAGSHIP / "strategies" / "sleeves" / "macd_one_shot.ms",
    "long_short_flip": FLAGSHIP / "strategies" / "sleeves" / "long_short_flip.ms",
}


@dataclass
class SleeveScore:
    sleeve: str
    ok: bool
    pass_gate: bool
    sharpe: float
    d_sharpe: float
    trades: int
    ret: float
    mdd: float
    error: str = ""


@dataclass
class TapeFeatures:
    roc_21: float
    roc_55: float
    vol_pct: float  # mean atr14/close proxy via high-low range
    trend_strength: float  # (close_end/close_start)-1
    chop: float  # 1 - |roc_21| / (sum abs day moves approx)


def passes(m: Metrics, bh: Metrics) -> bool:
    if not m.ok or not bh.ok:
        return False
    d = m.sharpe - bh.sharpe
    return m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25


def load_tape_features(tape: Path) -> TapeFeatures:
    rows: list[dict[str, str]] = []
    with tape.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 22:
        return TapeFeatures(0, 0, 0, 0, 0)
    closes = [float(r["close"]) for r in rows]
    highs = [float(r["high"]) for r in rows]
    lows = [float(r["low"]) for r in rows]
    n = len(closes)

    def roc(k: int) -> float:
        if n <= k or closes[-1 - k] == 0:
            return 0.0
        return closes[-1] / closes[-1 - k] - 1.0

    ranges = [(h - l) / c if c else 0.0 for h, l, c in zip(highs, lows, closes)]
    vol_pct = sum(ranges[-14:]) / min(14, len(ranges))
    day_moves = [abs(closes[i] / closes[i - 1] - 1.0) for i in range(1, n)]
    path = sum(day_moves[-21:]) if len(day_moves) >= 21 else sum(day_moves)
    net = abs(roc(21))
    chop = 1.0 - (net / path) if path > 1e-9 else 1.0
    return TapeFeatures(
        roc_21=roc(21),
        roc_55=roc(min(55, n - 1)),
        vol_pct=vol_pct,
        trend_strength=closes[-1] / closes[0] - 1.0 if closes[0] else 0.0,
        chop=chop,
    )


def score_sleeve(name: str, src: str, tape: Path, bh: Metrics) -> SleeveScore:
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    if not m.ok:
        return SleeveScore(name, False, False, 0, 0, 0, 0, 0, m.error[:120])
    d = m.sharpe - bh.sharpe if bh.ok else float("nan")
    return SleeveScore(
        sleeve=name,
        ok=True,
        pass_gate=passes(m, bh),
        sharpe=m.sharpe,
        d_sharpe=d,
        trades=m.trades,
        ret=m.total_return,
        mdd=m.max_drawdown,
    )


def pick_winner(scores: list[SleeveScore]) -> SleeveScore | None:
    """Prefer any pass_gate; among those max d_sharpe; else best d_sharpe with trades."""
    ok = [s for s in scores if s.ok]
    if not ok:
        return None
    passing = [s for s in ok if s.pass_gate]
    pool = passing if passing else [s for s in ok if s.trades >= 1]
    if not pool:
        pool = ok
    return max(pool, key=lambda s: (s.pass_gate, s.d_sharpe if not math.isnan(s.d_sharpe) else -999))


def mine_rules(rows: list[dict]) -> list[str]:
    """Crude feature → winner associations on eval_3m only."""
    eval_rows = [r for r in rows if r["window"] == "eval_3m" and r["winner"]]
    tips: list[str] = []
    by_winner: dict[str, list[dict]] = {}
    for r in eval_rows:
        by_winner.setdefault(r["winner"], []).append(r)

    for w, rs in sorted(by_winner.items()):
        avg_roc21 = sum(r["features"]["roc_21"] for r in rs) / len(rs)
        avg_vol = sum(r["features"]["vol_pct"] for r in rs) / len(rs)
        avg_chop = sum(r["features"]["chop"] for r in rs) / len(rs)
        avg_trend = sum(r["features"]["trend_strength"] for r in rs) / len(rs)
        tips.append(
            f"{w}: n={len(rs)} avg_roc21={avg_roc21:+.2%} avg_volPct={avg_vol:.3%} "
            f"avg_chop={avg_chop:.2f} avg_trend={avg_trend:+.2%} "
            f"syms=[{', '.join(r['symbol'] for r in rs)}]"
        )

    # Decision stumps vs v4 losses
    for r in eval_rows:
        if r["symbol"] in ("IWM", "AAPL", "MSFT") or r["winner"] != "v4":
            f = r["features"]
            tips.append(
                f"  route {r['symbol']}→{r['winner']} when "
                f"roc21={f['roc_21']:+.2%} roc55={f['roc_55']:+.2%} "
                f"vol={f['vol_pct']:.3%} chop={f['chop']:.2f}"
            )
    return tips


def main() -> int:
    # Pre-stitch / load sources
    sources: dict[str, str] = {}
    for name, path in SLEEVES.items():
        if not path.exists():
            print(f"missing sleeve {name}: {path}", file=sys.stderr)
            return 1
        # Class strategies need libs; plain strategy sleeves stitch harmlessly
        sources[name] = stitch_source(path)

    bh_src = buy_hold_source()
    report_rows: list[dict] = []
    print(f"{'win':10} {'sym':5} {'winner':16} {'dBH':8} {'sh':8} {'tr':4} {'ret':9}  all_passes")

    for win in WINDOWS:
        n_v4 = n_ceil = n = 0
        for sym in SYMS:
            tape = FLAGSHIP / "tapes" / win / f"{sym}.csv"
            if not tape.exists():
                print(f"missing tape {tape}", file=sys.stderr)
                continue
            n += 1
            bh = run_gene(bh_src, tape, execution="next-open", cost_bps=10)
            feats = load_tape_features(tape)
            scores = [score_sleeve(name, sources[name], tape, bh) for name in SLEEVES]
            by_name = {s.sleeve: s for s in scores}
            winner = pick_winner(scores)
            v4 = by_name["v4"]
            if v4.pass_gate:
                n_v4 += 1
            if winner and winner.pass_gate:
                n_ceil += 1

            passes_list = [s.sleeve for s in scores if s.pass_gate]
            wname = winner.sleeve if winner else "?"
            wd = winner.d_sharpe if winner else float("nan")
            print(
                f"{win:10} {sym:5} {wname:16} {wd:+8.3f} "
                f"{(winner.sharpe if winner else 0):+8.3f} "
                f"{(winner.trades if winner else 0):4d} "
                f"{(winner.ret if winner else 0):+9.2%}  "
                f"{passes_list or ['—']}"
            )
            report_rows.append(
                {
                    "window": win,
                    "symbol": sym,
                    "winner": wname,
                    "v4_pass": v4.pass_gate,
                    "ceiling_pass": bool(winner and winner.pass_gate),
                    "lift_over_v4": bool(winner and winner.pass_gate and not v4.pass_gate),
                    "features": asdict(feats),
                    "sleeves": [asdict(s) for s in scores],
                }
            )

        print(f"  >> {win}: v4={n_v4}/{n}  ceiling={n_ceil}/{n}  "
              f"lifted={sum(1 for r in report_rows if r['window']==win and r['lift_over_v4'])}")

    tips = mine_rules(report_rows)
    print("\n=== ENCODE HINTS (eval_3m) ===")
    for t in tips:
        print(t)

    # Ceiling summary
    eval_lift = [r for r in report_rows if r["window"] == "eval_3m" and r["lift_over_v4"]]
    print("\n=== CEILING LIFTS vs v4 (eval_3m) ===")
    if not eval_lift:
        print("  (none — oracle cannot beat v4 on failing names with this sleeve set)")
    for r in eval_lift:
        print(f"  {r['symbol']}: v4 fail → {r['winner']} PASS")

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / "ceiling_ensemble.json"
    md = RESULTS / "ceiling_ensemble.md"
    payload = {
        "sleeves": list(SLEEVES.keys()),
        "rows": report_rows,
        "encode_hints": tips,
        "summary": {
            "eval_3m_v4": sum(1 for r in report_rows if r["window"] == "eval_3m" and r["v4_pass"]),
            "eval_3m_ceiling": sum(1 for r in report_rows if r["window"] == "eval_3m" and r["ceiling_pass"]),
            "wf_v4": sum(1 for r in report_rows if r["window"] == "wf_2022q1" and r["v4_pass"]),
            "wf_ceiling": sum(1 for r in report_rows if r["window"] == "wf_2022q1" and r["ceiling_pass"]),
        },
    }
    out.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    s = payload["summary"]
    lift_lines = [f"- {r['symbol']}: -> `{r['winner']}`" for r in eval_lift] or ["- none"]
    hint_lines = [f"- {t}" for t in tips]
    md_lines = [
        "# Ceiling ensemble",
        "",
        "Oracle pick among sleeves (research only - not a live strategy).",
        "",
        f"- eval_3m: v4 **{s['eval_3m_v4']}/10** -> ceiling **{s['eval_3m_ceiling']}/10**",
        f"- wf_2022q1: v4 **{s['wf_v4']}/10** -> ceiling **{s['wf_ceiling']}/10**",
        "",
        "## Lifts",
        *lift_lines,
        "",
        "## Encode hints",
        *hint_lines,
        "",
    ]
    md.write_text("\n".join(md_lines), encoding="utf-8")
    print(f"\nwrote {rel(out)}")
    print(f"wrote {rel(md)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
