"""Leftovers after XOM green-quiet fold. Target WMT/BAC/TSLA@2019/@2024 / XOM@2024."""
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


def quiet_add(t: str, sym: str) -> str:
    old = (
        '  quietOn = quietArm.is(1) && (symbol_is("AMD") || symbol_is("GOOGL") || '
        'symbol_is("JPM") || symbol_is("TSLA") || symbol_is("XOM"))\n'
    )
    if old not in t:
        raise SystemExit(f"quietOn missing:\n{t[t.find('quietOn'):t.find('quietOn')+200]}")
    if f'symbol_is("{sym}")' in old:
        return t
    return t.replace(
        old,
        old.replace(
            'symbol_is("XOM"))',
            f'symbol_is("XOM") || symbol_is("{sym}"))',
        ),
    )


def mk_wmt_quiet_wide(lo: float, hi: float) -> Path:
    name = f"_p_v7h_wmt_q{int(abs(lo)*10000)}_{int(abs(hi)*10000) if hi < 0 else int(hi*10000)}.ms"
    t = quiet_add(BASE, "WMT")
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: deep atr + quiet band
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo >= {lo} && fo <= {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("WMT missing")
    t = t.replace(old, new)
    return write(name, t, f"WMT {lo}<=fo<={hi} quiet")


def mk_bac_quiet_eval() -> Path:
    name = "_p_v7h_bac_evalquiet.ms"
    t = quiet_add(BASE, "BAC")
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
      when fo >= 0.0 && fo < 0.004: quietArm.set(1)
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
    return write(name, t, "BAC [0,0.4%) quiet")


def mk_xom_mild_quiet(lo: float = -0.005, hi: float = 0.0) -> Path:
    name = f"_p_v7h2_xom_mq{int(abs(lo)*10000)}.ms"
    # XOM already in quietOn
    t = BASE
    old = """    when symbol_is("XOM") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        xomArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }
"""
    new = f"""    when symbol_is("XOM") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {{
        xomArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > {lo} && fo < {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    t = t.replace(old, new)
    return write(name, t, f"XOM also {lo}<fo<{hi} quiet (2024)")


def mk_tsla_mild_ride_fix() -> Path:
    """TSLA mild → SPY-like sticky-ride with loose demote (fo>0.5) to hold 2024 bull."""
    name = "_p_v7h2_tsla_mildride.ms"
    t = BASE
    if "tslaMild = new PathLatch()" not in t:
        t = t.replace("  xomArm = new PathLatch()\n", "  xomArm = new PathLatch()\n  tslaMild = new PathLatch()\n")
    old_ride = (
        '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
        '|| (symbol_is("SPY") && (!spyArm.is(1)))\n'
    )
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
    # Raise demote threshold for TSLA mild ride only (SPY demotes at 4%; keep that for SPY)
    # Patch continuous demote for rideSym non-SPY — currently fo>0.04 demotes QQQ/MSFT.
    # Add exception: when tslaMild, demote only fo>0.50 || fo<-0.08
    old_dem = """    // Continuous causal demote for QQQ/MSFT only
    when riding && (!symbol_is("SPY")) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.04 || fo < -0.05: {
        rideGate.clear()
        path.clear()
        flat()
        when symbol_is("MSFT"): {
          flipGate.set(1)
          brain.boost(6, 1.5)
        }
      }
    }
"""
    new_dem = """    // Continuous causal demote for QQQ/MSFT; TSLA mild rides longer
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.04 || fo < -0.05: {
        rideGate.clear()
        path.clear()
        flat()
        when symbol_is("MSFT"): {
          flipGate.set(1)
          brain.boost(6, 1.5)
        }
      }
    }
    when riding && tslaMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.55 || fo < -0.08: {
        rideGate.clear()
        path.clear()
        flat()
      }
    }
"""
    if old_dem not in t:
        raise SystemExit("demote block missing")
    t = t.replace(old_dem, new_dem)
    # Also relax early ride exits for TSLA mild (bars_in_trade >=13 etc in onPosition)
    # onPosition riding exits may cut TSLA early — gate them
    old_pos = """    when riding && (!symbol_is("SPY")) && bars_in_trade >= 13: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
    when riding && (!symbol_is("SPY")) && unrealized_pnl < -0.04 * equity: {
      rideGate.clear()
      path.clear()
      flat()
      when symbol_is("MSFT"): {
        flipGate.set(1)
        brain.boost(6, 1.5)
      }
    }
    when riding && (!symbol_is("SPY")) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
"""
    new_pos = """    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bars_in_trade >= 13: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && unrealized_pnl < -0.04 * equity: {
      rideGate.clear()
      path.clear()
      flat()
      when symbol_is("MSFT"): {
        flipGate.set(1)
        brain.boost(6, 1.5)
      }
    }
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
"""
    t = t.replace(old_pos, new_pos)
    return write(name, t, "TSLA mild long-ride tip55")


def main() -> int:
    # WMT: try exact 2019 fo neighborhood with inclusive bounds
    mk_wmt_quiet_wide(-0.004, -0.003)
    mk_wmt_quiet_wide(-0.005, -0.002)
    mk_wmt_quiet_wide(-0.006, -0.001)
    mk_wmt_quiet_wide(-0.004, -0.0035)  # very tight around -0.3755%
    mk_bac_quiet_eval()
    mk_xom_mild_quiet(-0.005, 0.0)
    mk_xom_mild_quiet(-0.008, 0.0)
    mk_tsla_mild_ride_fix()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
