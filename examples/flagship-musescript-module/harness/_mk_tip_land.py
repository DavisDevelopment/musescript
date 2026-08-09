#!/usr/bin/env python3
"""Extra seals (MSFT/SPY) + preferred land package on tip-robustness pass."""
from __future__ import annotations

from _mk_tip_robust import BASE, apply_jpm_seal, apply_wmt_seal, set_bac_tip, write

MSFT_TIP = """    // MSFT: hold + fo tip-lock above BH end (~19.8%)
    when stickyOn && symbol_is("MSFT") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.195: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""

SPY_TIP = """    // SPY deep-red sticky: tip-lock + soft stop
    when stickyOn && symbol_is("SPY") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.145: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""


def seal_msft(t: str) -> str:
    if "msftDone = new PathLatch()" not in t:
        t = t.replace(
            "  msftArm = new PathLatch()\n",
            "  msftArm = new PathLatch()\n  msftDone = new PathLatch()\n",
        )
    if "msftBar1Deep =" not in t:
        t = t.replace(
            '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n',
            '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n'
            '  msftBar1Deep = symbol_is("MSFT") && bar_index == 1 && ((close - open) / open) < -0.02\n',
        )
    old = '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2)))'
    new = (
        '&& (!msftBar1Deep)'
        ' && (!(symbol_is("MSFT") && (msftArm.is(1) || msftDone.is(1) || bar_index < 2)))'
    )
    if old not in t:
        raise SystemExit("MSFT crown bit missing")
    t = t.replace(old, new)
    new_tip = """    // MSFT sticky tip (series msftBar1Deep + msftDone seal)
    when stickyOn && symbol_is("MSFT") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.195: {
        stickyGate.clear()
        msftDone.set(1)
        path.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      msftDone.set(1)
      path.clear()
      flat()
    }
"""
    if MSFT_TIP not in t:
        raise SystemExit("MSFT_TIP missing")
    return t.replace(MSFT_TIP, new_tip)


def seal_spy(t: str) -> str:
    if "spyDone = new PathLatch()" not in t:
        t = t.replace(
            "  spyArm = new PathLatch()\n",
            "  spyArm = new PathLatch()\n  spyDone = new PathLatch()\n",
        )
    if "spyBar1Deep =" not in t:
        # may already have msftBar1Deep inserted
        if "msftBar1Deep =" in t:
            t = t.replace(
                '  msftBar1Deep = symbol_is("MSFT") && bar_index == 1 && ((close - open) / open) < -0.02\n',
                '  msftBar1Deep = symbol_is("MSFT") && bar_index == 1 && ((close - open) / open) < -0.02\n'
                '  spyBar1Deep = symbol_is("SPY") && bar_index == 1 && ((close - open) / open) < -0.015\n',
            )
        else:
            t = t.replace(
                '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n',
                '  bacBar1Sticky = symbol_is("BAC") && bar_index == 1 && ((close - open) / open) < 0.004\n'
                '  spyBar1Deep = symbol_is("SPY") && bar_index == 1 && ((close - open) / open) < -0.015\n',
            )
    old = '&& (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2)))'
    new = (
        '&& (!spyBar1Deep)'
        ' && (!(symbol_is("SPY") && (spyArm.is(1) || spyDone.is(1) || bar_index < 2)))'
    )
    if old not in t:
        raise SystemExit("SPY crown bit missing")
    t = t.replace(old, new)
    new_tip = """    // SPY deep-red sticky (series spyBar1Deep + spyDone seal)
    when stickyOn && symbol_is("SPY") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.145: {
        stickyGate.clear()
        spyDone.set(1)
        path.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      spyDone.set(1)
      path.clear()
      flat()
    }
"""
    if SPY_TIP not in t:
        raise SystemExit("SPY_TIP missing")
    return t.replace(SPY_TIP, new_tip)


def main() -> int:
    # preferred land: JPM+WMT seals, keep BAC tip 10% (safer); tip105 documented as optional
    t = apply_wmt_seal(apply_jpm_seal(BASE))
    write("_p_v7h7_land_seals.ms", t, "LAND: JPM+WMT Bar1+Done seals (BAC tip stays 10%)")

    t = apply_wmt_seal(apply_jpm_seal(set_bac_tip(BASE, tip=0.105)))
    write("_p_v7h7_land_pref.ms", t, "LAND: JPM+WMT seals + BAC tip 10.5")

    write("_p_v7h7_msft_seal.ms", seal_msft(BASE), "MSFT Bar1Deep+Done tip19.5")
    write("_p_v7h7_spy_seal.ms", seal_spy(BASE), "SPY Bar1Deep+Done tip14.5")
    write(
        "_p_v7h7_four_seal.ms",
        seal_spy(seal_msft(apply_wmt_seal(apply_jpm_seal(BASE)))),
        "JPM+WMT+MSFT+SPY Done/Bar1 seals",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
