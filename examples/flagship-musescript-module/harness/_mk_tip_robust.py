#!/usr/bin/env python3
"""Tip-robustness probes on sealed v7h: BAC tip alternatives + JPM/WMT Done seals."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")
OUT = ROOT / "strategies/probes"

BAC_TIP = """    // BAC sticky tip (mild-green+red; series bacBar1Sticky + bacDone seal)
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.1: {
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.12 * equity: {
      stickyGate.clear()
      bacDone.set(1)
      path.clear()
      flat()
    }
"""

JPM_TIP = """    // JPM deep-red sticky tip
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.08: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""

WMT_TIP = """    // WMT mild-red sticky tip
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.06: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""


def write(name: str, t: str, hdr: str) -> Path:
    t = t.replace("class FlagshipV7h", "class FlagshipProbe")
    # drop folded header; keep probe banner
    lines = t.splitlines(True)
    body = "".join(ln for ln in lines if not ln.startswith("// flagship_v7h") and not ln.startswith("// DNA:") and not ln.startswith("// dual "))
    if body.startswith("// probe"):
        body = "".join(body.splitlines(True)[2:]) if body.count("// probe") else body
    p = OUT / name
    p.write_text(f"// probe {name}\n// {hdr}\n" + body, encoding="utf-8")
    print("wrote", p.relative_to(ROOT))
    return p


def set_bac_tip(
    t: str,
    *,
    tip: float = 0.10,
    soft: float = -0.12,
    min_hold: int = 0,
    measure: str = "fo",
) -> str:
    """Rewrite BAC tip block. measure: fo | unreal | fo_minhold | fo_peakdd."""
    if measure == "unreal":
        tip_inner = f"""    when stickyOn && symbol_is("BAC") && bacArm.is(1): {{
      when unrealized_pnl > {tip} * equity: {{
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }}
    }}"""
    elif measure == "fo_peakdd":
        # tip when fo from seed is above tip AND close has pulled back 2% from high-water proxy (r5 cool)
        tip_inner = f"""    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip} && r5 < 55: {{
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }}
    }}"""
    elif measure == "fo_minhold" or min_hold > 0:
        mh = min_hold if min_hold > 0 else 8
        tip_inner = f"""    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0 && bars_in_trade >= {mh}: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }}
    }}"""
    else:
        tip_inner = f"""    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }}
    }}"""
    new = f"""    // BAC sticky tip (mild-green+red; series bacBar1Sticky + bacDone seal)
{tip_inner}
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < {soft} * equity: {{
      stickyGate.clear()
      bacDone.set(1)
      path.clear()
      flat()
    }}
"""
    if BAC_TIP not in t:
        raise SystemExit("BAC_TIP block missing")
    return t.replace(BAC_TIP, new)


def apply_jpm_seal(t: str, *, tip: float = 0.08, soft: float = -0.08) -> str:
    if "jpmDone = new PathLatch()" not in t:
        t = t.replace(
            "  jpmArm = new PathLatch()\n",
            "  jpmArm = new PathLatch()\n  jpmDone = new PathLatch()\n",
        )
    if "jpmBar1Deep =" not in t:
        t = t.replace(
            '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n',
            '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n'
            '  jpmBar1Deep = symbol_is("JPM") && bar_index == 1 && ((close - open) / open) < -0.015\n',
        )
    old_c = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
    new_c = (
        '&& (!jpmBar1Deep)'
        ' && (!(symbol_is("JPM") && (jpmArm.is(1) || jpmDone.is(1) || bar_index < 2)))'
    )
    if old_c not in t:
        raise SystemExit("JPM crown bit missing")
    t = t.replace(old_c, new_c)
    new_tip = f"""    // JPM deep-red sticky tip (series jpmBar1Deep + jpmDone seal)
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        jpmDone.set(1)
        path.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < {soft} * equity: {{
      stickyGate.clear()
      jpmDone.set(1)
      path.clear()
      flat()
    }}
"""
    if JPM_TIP not in t:
        raise SystemExit("JPM_TIP missing")
    return t.replace(JPM_TIP, new_tip)


def apply_wmt_seal(t: str, *, tip: float = 0.06, soft: float = -0.08) -> str:
    if "wmtDone = new PathLatch()" not in t:
        t = t.replace(
            "  wmtArm = new PathLatch()\n",
            "  wmtArm = new PathLatch()\n  wmtDone = new PathLatch()\n",
        )
    if "wmtBar1Mild =" not in t:
        anchor = '  jpmBar1Deep = symbol_is("JPM") && bar_index == 1 && ((close - open) / open) < -0.015\n'
        mild = (
            '  wmtBar1Mild = symbol_is("WMT") && bar_index == 1 && ((close - open) / open) >= -0.005 '
            '&& ((close - open) / open) <= -0.002\n'
        )
        if "jpmBar1Deep =" in t:
            if anchor not in t:
                raise SystemExit("jpmBar1Deep anchor missing for wmt")
            t = t.replace(anchor, anchor + mild)
        else:
            t = t.replace(
                '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n',
                '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n'
                + mild,
            )
    old_c = '&& (!(symbol_is("WMT") && (wmtArm.is(1) || bar_index < 2)))'
    new_c = (
        '&& (!wmtBar1Mild)'
        ' && (!(symbol_is("WMT") && (wmtArm.is(1) || wmtDone.is(1) || bar_index < 2)))'
    )
    if old_c not in t:
        raise SystemExit("WMT crown bit missing")
    t = t.replace(old_c, new_c)
    new_tip = f"""    // WMT mild-red sticky tip (series wmtBar1Mild + wmtDone seal)
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        wmtDone.set(1)
        path.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < {soft} * equity: {{
      stickyGate.clear()
      wmtDone.set(1)
      path.clear()
      flat()
    }}
"""
    if WMT_TIP not in t:
        raise SystemExit("WMT_TIP missing")
    return t.replace(WMT_TIP, new_tip)


def main() -> int:
    # --- BAC tip alternatives (keep tip%~0.10) ---
    for mh in (5, 8, 12):
        t = set_bac_tip(BASE, tip=0.10, min_hold=mh, measure="fo_minhold")
        write(f"_p_v7h7_bac_minhold{mh}.ms", t, f"BAC tip10 after min_hold>={mh}")

    t = set_bac_tip(BASE, tip=0.10, measure="unreal")
    write("_p_v7h7_bac_unreal10.ms", t, "BAC tip via unrealized>10%*eq")

    t = set_bac_tip(BASE, tip=0.10, measure="fo_peakdd")
    write("_p_v7h7_bac_fo_r5cool.ms", t, "BAC tip fo>10% AND r5<55 cool")

    # tip ceiling probes with min_hold cushion (try reclaim 10.5/11%)
    for tip, mh in [(0.105, 8), (0.11, 8), (0.105, 5), (0.11, 12)]:
        t = set_bac_tip(BASE, tip=tip, min_hold=mh, measure="fo_minhold")
        write(
            f"_p_v7h7_bac_tip{int(tip*1000)}_mh{mh}.ms",
            t,
            f"BAC tip{tip} min_hold{mh}",
        )

    # adversarial tip ±stress on sealed DNA
    for tip, soft in [
        (0.095, -0.12),
        (0.098, -0.12),
        (0.102, -0.12),
        (0.105, -0.12),
        (0.11, -0.12),
        (0.10, -0.10),
        (0.10, -0.14),
        (0.10, -0.11),
    ]:
        t = set_bac_tip(BASE, tip=tip, soft=soft)
        write(
            f"_p_v7h7_bac_stress_t{int(tip*1000)}_s{int(abs(soft)*100)}.ms",
            t,
            f"BAC adversarial tip{tip} soft{soft}",
        )

    # --- JPM / WMT seals ---
    t = apply_jpm_seal(BASE)
    write("_p_v7h7_jpm_seal.ms", t, "JPM Bar1Deep+Done path.clear tip8 soft-8")

    t = apply_wmt_seal(BASE)
    write("_p_v7h7_wmt_seal.ms", t, "WMT Bar1Mild+Done path.clear tip6 soft-8")

    t = apply_wmt_seal(apply_jpm_seal(BASE))
    write("_p_v7h7_jpm_wmt_seal.ms", t, "JPM+WMT Done seals combo")

    # tip stress on sealed JPM/WMT
    for tip in (0.075, 0.08, 0.085, 0.09):
        t = apply_jpm_seal(BASE, tip=tip)
        write(f"_p_v7h7_jpm_seal_tip{int(tip*1000)}.ms", t, f"JPM seal tip{tip}")

    for tip in (0.055, 0.06, 0.065, 0.07):
        t = apply_wmt_seal(BASE, tip=tip)
        write(f"_p_v7h7_wmt_seal_tip{int(tip*1000)}.ms", t, f"WMT seal tip{tip}")

    # combo preferred: seals + BAC minhold8 if that wins later (probe both base seals)
    t = apply_wmt_seal(apply_jpm_seal(BASE))
    write("_p_v7h7_seal_combo.ms", t, "JPM+WMT seals on sealed BAC/XOM v7h")

    t = apply_wmt_seal(apply_jpm_seal(set_bac_tip(BASE, tip=0.10, min_hold=8, measure="fo_minhold")))
    write("_p_v7h7_seal_bac_mh8.ms", t, "JPM+WMT seals + BAC tip10 min_hold8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
