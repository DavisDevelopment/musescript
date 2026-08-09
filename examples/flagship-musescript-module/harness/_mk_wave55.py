"""WMT band sticky (not quiet) + XOM 2024 abs-sharpe attacks + BAC tip-ride."""
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


def mk_wmt_band_sticky(tip: float = 0.055) -> Path:
    name = f"_p_v7h2_wmt_stickytip{int(tip*1000)}.ms"
    t = BASE
    if "wmtArm = new PathLatch()" not in t:
        t = t.replace("  xomArm = new PathLatch()\n", "  xomArm = new PathLatch()\n  wmtArm = new PathLatch()\n")
    old_s = '(symbol_is("JPM") && jpmArm.is(1))) && stickyGate.is(1)'
    if '(symbol_is("WMT") && wmtArm.is(1))' not in t:
        t = t.replace(
            old_s,
            '(symbol_is("JPM") && jpmArm.is(1)) || (symbol_is("WMT") && wmtArm.is(1))) && stickyGate.is(1)',
        )
    # mute crown while wmt sticky (and early bars when armed)
    crown = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
    if 'symbol_is("WMT") && (wmtArm.is(1)' not in t:
        t = t.replace(
            crown,
            crown + ' && (!(symbol_is("WMT") && (wmtArm.is(1) || bar_index < 2)))',
        )
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: deep atr + mild-red sticky (2019 -0.37%)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo >= -0.005: {{
        when fo <= -0.002: {{
          wmtArm.set(1)
          stickyGate.set(1)
          path.set(5)
          tickFill()
          long()
        }}
      }}
      primed.set(1)
    }}
"""
    t = t.replace(old, new)
    tip_block = f"""    // WMT mild-red sticky tip
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    t = t.replace(
        "    // SPY deep-red sticky: tip-lock + soft stop\n",
        tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n",
    )
    if "(!wmtArm.is(1))" not in t:
        t = t.replace(
            "(!jpmArm.is(1)) && bar_index >= 55",
            "(!jpmArm.is(1)) && (!wmtArm.is(1)) && bar_index >= 55",
        )
        t = t.replace(
            "(!jpmArm.is(1)) && bar_index >= 14",
            "(!jpmArm.is(1)) && (!wmtArm.is(1)) && bar_index >= 14",
        )
    return write(name, t, f"WMT nested band sticky tip>{tip:.1%}")


def mk_tsla_spy_ride() -> Path:
    """TSLA mild → SPY-style sticky-ride exits (bars>=55 r5) instead of QQQ demote."""
    name = "_p_v7h2_tsla_spystyle.ms"
    t = BASE
    if "tslaMild = new PathLatch()" not in t:
        t = t.replace("  xomArm = new PathLatch()\n", "  xomArm = new PathLatch()\n  tslaMild = new PathLatch()\n")
    old_ride = (
        '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
        '|| (symbol_is("SPY") && (!spyArm.is(1)))\n'
    )
    # Treat TSLA mild like SPY for rideSym inclusion AND in SPY exit branches
    t = t.replace(
        old_ride,
        old_ride.replace(
            '(symbol_is("SPY") && (!spyArm.is(1)))',
            '(symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("TSLA") && tslaMild.is(1))',
        ),
    )
    old = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      primed.set(1)
    }
"""
    new = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    # Rewrite ride exits that say (!symbol_is("SPY")) to also exclude tslaMild
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && bars_in_trade >= 13:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bars_in_trade >= 13:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && unrealized_pnl < -0.04 * equity:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && unrealized_pnl < -0.04 * equity:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && bar_index >= 2 && seedOpen.get() > 0.0:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bar_index >= 2 && seedOpen.get() > 0.0:",
    )
    # Extend SPY sticky-ride exits to tslaMild
    for old_spy, new_spy in [
        (
            'when riding && symbol_is("SPY") && bars_in_trade >= 55 && r5 < 45:',
            'when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 55 && r5 < 45:',
        ),
        (
            'when riding && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.04 * equity:',
            'when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 14 && unrealized_pnl < -0.04 * equity:',
        ),
        (
            'when riding && symbol_is("SPY") && bar_index >= 2 && seedOpen.get() > 0.0: {\n'
            '      fo = (close - seedOpen.get()) / seedOpen.get()\n'
            '      when fo > 0.04: {',
            'when riding && symbol_is("SPY") && bar_index >= 2 && seedOpen.get() > 0.0: {\n'
            '      fo = (close - seedOpen.get()) / seedOpen.get()\n'
            '      when fo > 0.04: {',
        ),
    ]:
        if old_spy in t:
            t = t.replace(old_spy, new_spy)
    # Add TSLA tip demote at 55%
    tip = """    when riding && tslaMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.55: {
        rideGate.clear()
        path.clear()
        flat()
      }
    }
"""
    t = t.replace("    when riding: long()\n", tip + "    when riding: long()\n")
    return write(name, t, "TSLA mild SPY-style ride + tip55")


def mk_xom_2024_quiet_hi() -> Path:
    """Widen XOM quiet into mild red for 2024 -0.34%."""
    name = "_p_v7h2_xom_quiet_incl_mildred.ms"
    t = BASE
    old = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
"""
    # also quiet mild red and flat
    new = """      when fo > -0.005 && fo < 0.005: quietArm.set(1)
"""
    t = t.replace(old, new)
    return write(name, t, "XOM |fo|<0.5% quiet incl 2024 mild red")


def main() -> int:
    mk_wmt_band_sticky(0.05)
    mk_wmt_band_sticky(0.06)
    mk_wmt_band_sticky(0.07)
    mk_tsla_spy_ride()
    mk_xom_2024_quiet_hi()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
