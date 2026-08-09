#!/usr/bin/env python3
"""Build harden probes for XOM short + BAC seal from flagship_v7h.ms."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")
OUT = ROOT / "strategies/probes"


def write(name: str, t: str, hdr: str) -> Path:
    t = t.replace("class FlagshipV7h", "class FlagshipProbe")
    p = OUT / name
    p.write_text(f"// probe {name}\n// {hdr}\n" + t, encoding="utf-8")
    print("wrote", p.relative_to(ROOT))
    return p


def apply_xom_harden(
    t: str,
    *,
    tip_dn: float = -0.10,
    cover_up: float = 0.05,
    hold: int = 55,
    alt_r5: float = 30.0,
    alt_min_bars: int = 18,
) -> str:
    """Series-time xomBar1Mild + xomDone seal; wider cover; RSI alt exit; keep tip."""
    if "xomDone = new PathLatch()" not in t:
        t = t.replace(
            "  xomShort = new PathLatch()\n",
            "  xomShort = new PathLatch()\n  xomDone = new PathLatch()\n",
        )
    if "xomBar1Mild =" not in t:
        t = t.replace(
            '  nvdaBar1Deep = symbol_is("NVDA") && bar_index == 1 && ((close - open) / open) < -0.04\n',
            '  nvdaBar1Deep = symbol_is("NVDA") && bar_index == 1 && ((close - open) / open) < -0.04\n'
            '  xomBar1Mild = symbol_is("XOM") && bar_index == 1 && ((close - open) / open) > -0.005 && ((close - open) / open) < 0.0\n',
        )
    # crown: series-time + done seal
    old_c = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2))) && (!(symbol_is("XOM") && xomShort.is(1)))'
    new_c = (
        '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
        ' && (!xomBar1Mild)'
        ' && (!(symbol_is("XOM") && (xomShort.is(1) || xomDone.is(1))))'
    )
    if old_c not in t:
        raise SystemExit("xom crown bit missing")
    t = t.replace(old_c, new_c)

    old_tip = """    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < -0.1: {
        xomShort.clear()
        path.clear()
        flat()
      }
      when fo > 0.04: {
        xomShort.clear()
        path.clear()
        flat()
      }
    }
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 50: {
      xomShort.clear()
      path.clear()
      flat()
    }
"""
    new_tip = f"""    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < {tip_dn}: {{
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }}
      when fo > {cover_up}: {{
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }}
    }}
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= {alt_min_bars} && r5 < {alt_r5}: {{
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }}
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= {hold}: {{
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }}
"""
    if old_tip not in t:
        raise SystemExit("xom tip block missing")
    return t.replace(old_tip, new_tip)


def apply_bac_harden(t: str, *, tip: float = 0.10, soft: float = -0.12) -> str:
    """Series-time bacBar1Sticky + bacDone on tip/soft; path.clear; keep bacArm mute."""
    if "bacDone = new PathLatch()" not in t:
        t = t.replace(
            "  bacArm = new PathLatch()\n",
            "  bacArm = new PathLatch()\n  bacDone = new PathLatch()\n",
        )
    if "bacBar1Sticky =" not in t:
        # mild-green OR any red (not atr fo>=0.004); insert after bar1Deep block
        insert_after = (
            '  nvdaBar1Deep = symbol_is("NVDA") && bar_index == 1 && ((close - open) / open) < -0.04\n'
        )
        if "xomBar1Mild =" in t:
            insert_after = (
                '  xomBar1Mild = symbol_is("XOM") && bar_index == 1 && '
                '((close - open) / open) > -0.005 && ((close - open) / open) < 0.0\n'
            )
        if insert_after not in t:
            raise SystemExit("bacBar1Sticky insert anchor missing")
        t = t.replace(
            insert_after,
            insert_after
            + '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n',
        )
    old_c = '&& (!(symbol_is("BAC") && (bacArm.is(1) || bar_index < 2)))'
    new_c = (
        '&& (!bacBar1Sticky)'
        ' && (!(symbol_is("BAC") && (bacArm.is(1) || bacDone.is(1) || bar_index < 2)))'
    )
    if old_c not in t:
        raise SystemExit("bac crown bit missing")
    t = t.replace(old_c, new_c)

    old_tip = """    // BAC sticky tip (mild-green+red; crown sealed via bacArm mute)
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.1: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.12 * equity: {
      stickyGate.clear()
      flat()
    }
"""
    new_tip = f"""    // BAC sticky tip (mild-green+red; series bacBar1Sticky + bacDone seal)
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        bacDone.set(1)
        path.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < {soft} * equity: {{
      stickyGate.clear()
      bacDone.set(1)
      path.clear()
      flat()
    }}
"""
    if old_tip not in t:
        raise SystemExit("bac tip block missing")
    return t.replace(old_tip, new_tip)


def main() -> int:
    # A: XOM harden only
    t = apply_xom_harden(BASE)
    write("_p_v7h6_xom_harden.ms", t, "XOM mild-red harden: Bar1Mild+Done cover5% hold55 alt r5<30")

    # B: BAC harden only
    t = apply_bac_harden(BASE)
    write("_p_v7h6_bac_harden.ms", t, "BAC tip seal: Bar1Sticky+Done path.clear tip10 soft-12")

    # C: both
    t = apply_bac_harden(apply_xom_harden(BASE))
    write("_p_v7h6_xom_bac_harden.ms", t, "XOM+BAC harden combo")

    # D: XOM cover variants
    for cover, hold, tip_dn in [
        (0.045, 50, -0.10),
        (0.05, 55, -0.10),
        (0.055, 55, -0.10),
        (0.05, 55, -0.09),
        (0.05, 60, -0.10),
        (0.06, 55, -0.10),
    ]:
        t = apply_xom_harden(BASE, tip_dn=tip_dn, cover_up=cover, hold=hold)
        write(
            f"_p_v7h6_xom_c{int(cover*1000)}_h{hold}_t{int(abs(tip_dn)*100)}.ms",
            t,
            f"XOM harden cover{cover} hold{hold} tip{tip_dn}",
        )

    # E: BAC tip stress ±
    for tip, soft in [
        (0.095, -0.12),
        (0.10, -0.12),
        (0.105, -0.12),
        (0.11, -0.12),
        (0.10, -0.10),
        (0.10, -0.14),
        (0.102, -0.12),
    ]:
        t = apply_bac_harden(BASE, tip=tip, soft=soft)
        write(
            f"_p_v7h6_bac_tip{int(tip*1000)}_s{int(abs(soft)*100)}.ms",
            t,
            f"BAC seal tip{tip} soft{soft}",
        )

    # F: combo preferred candidate
    t = apply_bac_harden(
        apply_xom_harden(BASE, tip_dn=-0.10, cover_up=0.05, hold=55, alt_r5=30, alt_min_bars=18),
        tip=0.10,
        soft=-0.12,
    )
    write("_p_v7h6_combo_pref.ms", t, "preferred XOM cover5%/Done/Bar1 + BAC Done/Bar1 tip10")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
