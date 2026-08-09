#!/usr/bin/env python3
"""Build preferred land + alt-exit harden probes."""
from __future__ import annotations

from pathlib import Path

from _mk_harden_tip import BASE, apply_bac_harden, apply_xom_harden, write

ROOT = Path(__file__).resolve().parents[1]


def _strip_dead_alt(t: str) -> str:
    dead = """    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 999 && r5 < 0: {
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }
"""
    return t.replace(dead, "")


def _swap_tip(t: str, tip_block: str) -> str:
    t = _strip_dead_alt(
        apply_xom_harden(t, tip_dn=-0.10, cover_up=0.05, hold=55, alt_r5=0, alt_min_bars=999)
    )
    old = """    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < -0.1: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
      when fo > 0.05: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
    }
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 55: {
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }
"""
    if old not in t:
        raise SystemExit("tip anchor missing after harden")
    return t.replace(old, tip_block)


BASE_TIP = """    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < -0.1: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
      when fo > 0.05: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
    }
"""
HOLD = """    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 55: {
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }
"""


def main() -> int:
    alt_r5hi = (
        BASE_TIP
        + """    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 14 && r5 > 65: {
      xomShort.clear()
      xomDone.set(1)
      path.clear()
      flat()
    }
"""
        + HOLD
    )
    write("_p_v7h6_xom_alt_r5hi.ms", _swap_tip(BASE, alt_r5hi), "cover5 hold55 alt r5>65")

    alt_rise = (
        BASE_TIP
        + """    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 10 && rising(close, 3) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > -0.03: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
    }
"""
        + HOLD
    )
    write("_p_v7h6_xom_alt_rise.ms", _swap_tip(BASE, alt_rise), "cover5 hold55 alt rising")

    alt_soft = (
        BASE_TIP
        + """    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 30 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < -0.06: {
        xomShort.clear()
        xomDone.set(1)
        path.clear()
        flat()
      }
    }
"""
        + HOLD
    )
    write("_p_v7h6_xom_alt_softtp.ms", _swap_tip(BASE, alt_soft), "cover5 hold55 alt softTP")

    # preferred land: seal+cover5+hold55, no fragile RSI-oversold alt; + BAC seal
    pref = apply_bac_harden(
        apply_xom_harden(BASE, tip_dn=-0.10, cover_up=0.05, hold=55, alt_r5=0, alt_min_bars=999)
    )
    pref = _strip_dead_alt(pref)
    # Cleaner alt: soft time TP (non-fragile) — include if it holds board
    # Keep land tip block as-is from harden (cover5/hold55 only)
    write(
        "_p_v7h6_land_pref.ms",
        pref,
        "LAND: XOM Bar1Mild+Done cover5% hold55 + BAC Bar1Sticky+Done tip10",
    )

    # land + softTP alt
    land_soft = apply_bac_harden(_swap_tip(BASE, alt_soft))
    write(
        "_p_v7h6_land_softtp.ms",
        land_soft,
        "LAND+softTP: XOM cover5 hold55 soft-6%@30 + BAC seal",
    )

    # land + r5hi alt
    land_r5 = apply_bac_harden(_swap_tip(BASE, alt_r5hi))
    write(
        "_p_v7h6_land_r5hi.ms",
        land_r5,
        "LAND+r5hi: XOM cover5 hold55 r5>65 + BAC seal",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
