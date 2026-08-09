"""Last two fails: BAC@eval and XOM@2024."""
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


def mk_xom_quiet_red() -> Path:
    name = "_p_v7h4_xom_quiet_mildred.ms"
    t = BASE
    old = "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
    new = (
        "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
        "      when fo > -0.005 && fo < 0.0: quietArm.set(1)\n"
    )
    t = t.replace(old, new)
    return write(name, t, "XOM mild-red also quiet")


def mk_xom_fall_short() -> Path:
    name = "_p_v7h4_xom_fallshort.ms"
    t = BASE
    old = "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
    new = (
        "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
        "      when fo > -0.005 && fo < 0.0: quietArm.set(1)\n"
    )
    t = t.replace(old, new)
    # strengthen XOM quiet shorts
    inject = """    when quietOn && symbol_is("XOM") && falling(close, 2): {
      when position() == 0: tickFill()
      path.set(9)
      short()
    }
"""
    t = t.replace(
        "    when quietOn && r5 > 70: {",
        inject + "    when quietOn && r5 > 70: {",
    )
    return write(name, t, "XOM quiet + fall short bias")


def mk_xom_mute_flat(until: int = 40) -> Path:
    """Mild red: mute crown bars<until (no quiet) — hope one late trade or tr from elsewhere.
    Need trades>=1: allow crown after until."""
    name = f"_p_v7h4_xom_mute{until}.ms"
    t = BASE
    if "xomMild = new PathLatch()" not in t:
        t = t.replace("  tslaMild = new PathLatch()\n", "  tslaMild = new PathLatch()\n  xomMild = new PathLatch()\n")
    crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
    if f"xomMild.is(1) && bar_index < {until}" not in t:
        t = t.replace(
            crown,
            crown + f' && (!(symbol_is("XOM") && xomMild.is(1) && bar_index < {until}))',
        )
    old = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
"""
    new = f"""      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: xomMild.set(1)
"""
    t = t.replace(old, new)
    return write(name, t, f"XOM mild-red crown mute <{until}")


def mk_bac_spy_ride() -> Path:
    name = "_p_v7h4_bac_spystyle.ms"
    t = BASE
    if "bacMild = new PathLatch()" not in t:
        t = t.replace("  tslaMild = new PathLatch()\n", "  tslaMild = new PathLatch()\n  bacMild = new PathLatch()\n")
    old_ride = (
        '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
        '|| (symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("TSLA") && tslaMild.is(1))\n'
    )
    t = t.replace(
        old_ride,
        old_ride.replace(
            '(symbol_is("TSLA") && tslaMild.is(1))',
            '(symbol_is("TSLA") && tslaMild.is(1)) || (symbol_is("BAC") && bacMild.is(1))',
        ),
    )
    # remove BAC from atr for mild green; keep hot atr
    old = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: atrGate.set(1)
      when fo < 0.0: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0 && fo < 0.004: {
        bacMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo >= 0.004: atrGate.set(1)
      when fo < 0.0: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    # SPY-style exits for bacMild like tslaMild
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bars_in_trade >= 13:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && (!bacMild.is(1)) && bars_in_trade >= 13:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && unrealized_pnl < -0.04 * equity:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && (!bacMild.is(1)) && unrealized_pnl < -0.04 * equity:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && (!bacMild.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
    )
    t = t.replace(
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && bar_index >= 2 && seedOpen.get() > 0.0:",
        "when riding && (!symbol_is(\"SPY\")) && (!tslaMild.is(1)) && (!bacMild.is(1)) && bar_index >= 2 && seedOpen.get() > 0.0:",
    )
    t = t.replace(
        'when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 55 && r5 < 45:',
        'when riding && (symbol_is("SPY") || tslaMild.is(1) || bacMild.is(1)) && bars_in_trade >= 55 && r5 < 45:',
    )
    t = t.replace(
        'when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 14 && unrealized_pnl < -0.04 * equity:',
        'when riding && (symbol_is("SPY") || tslaMild.is(1) || bacMild.is(1)) && bars_in_trade >= 14 && unrealized_pnl < -0.04 * equity:',
    )
    tip = """    when riding && bacMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.10: {
        rideGate.clear()
        path.clear()
        flat()
      }
    }
"""
    if "bacMild.is(1) && bar_index >= 2" not in t:
        t = t.replace(
            "    when riding && tslaMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0:",
            tip + "    when riding && tslaMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0:",
        )
    return write(name, t, "BAC mild-green SPY-ride tip10")


def mk_bac_sticky_loose() -> Path:
    name = "_p_v7h4_bac_sticky_loose.ms"
    t = BASE
    old = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: atrGate.set(1)
      when fo < 0.0: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0 && fo < 0.004: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo >= 0.004: atrGate.set(1)
      when fo < 0.0: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    # loosen BAC soft stop tip10 stays; change -8% to -12%
    t = t.replace(
        """    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
""",
        """    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.12 * equity: {
      stickyGate.clear()
      flat()
    }
""",
    )
    # tip to 0.105
    t = t.replace(
        """    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.1: {
""",
        """    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.105: {
""",
    )
    return write(name, t, "BAC mild-green sticky tip10.5 soft-12%")


def main() -> int:
    mk_xom_quiet_red()
    mk_xom_fall_short()
    mk_xom_mute_flat(30)
    mk_xom_mute_flat(40)
    mk_bac_spy_ride()
    mk_bac_sticky_loose()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
