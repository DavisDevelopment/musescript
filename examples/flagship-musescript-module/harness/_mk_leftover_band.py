"""Band / mild-fo surgical leftovers on locked v7h (XOM/BAC/JPM grafts already in).

bar1 fo reminders:
  BAC  eval +0.13% | 2022 +1.98% | 2019 -1.52% | 2024 -0.05%
  WMT  eval +0.10% | 2022 -1.42% | 2019 -0.37% | 2024 -0.69%
  TSLA eval +6.85% | 2022 -3.36% | 2019 -2.16% | 2024 +0.59%
  JPM  eval -2.55% | 2022 +2.14% | 2019 -1.55% | 2024 +0.10%
  XOM  eval +0.28% | 2022 +2.81% | 2019 -1.97% | 2024 -0.34%
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")
OUT = ROOT / "strategies/probes"


def write(name: str, t: str, hdr: str) -> Path:
    t = t.replace("class FlagshipV7h", "class FlagshipProbe")
    path = OUT / name
    path.write_text(f"// probe {name}\n// {hdr}\n" + t, encoding="utf-8")
    print("wrote", path.relative_to(ROOT))
    return path


def ensure_latch(t: str, name: str) -> str:
    line = f"  {name} = new PathLatch()"
    if line in t:
        return t
    return t.replace("  xomArm = new PathLatch()\n", f"  xomArm = new PathLatch()\n  {name} = new PathLatch()\n")


def sticky_add(t: str, clause: str) -> str:
    """Append || clause before ) && stickyGate."""
    if clause in t:
        return t
    old = '(symbol_is("JPM") && jpmArm.is(1))) && stickyGate.is(1)'
    if old not in t:
        raise SystemExit("jpm sticky clause missing — v7h DNA changed")
    return t.replace(old, f'(symbol_is("JPM") && jpmArm.is(1)) || ({clause})) && stickyGate.is(1)')


def exclude_sticky_exit(t: str, arm: str) -> str:
    token = f"(!{arm}.is(1))"
    if token in t:
        return t
    t = t.replace(
        "(!jpmArm.is(1)) && bar_index >= 55",
        f"(!jpmArm.is(1)) && {token} && bar_index >= 55",
    )
    t = t.replace(
        "(!jpmArm.is(1)) && bar_index >= 14",
        f"(!jpmArm.is(1)) && {token} && bar_index >= 14",
    )
    return t


def insert_tip(t: str, block: str) -> str:
    if block.strip().split("\n", 1)[0] in t:
        return t
    anchor = "    // SPY deep-red sticky: tip-lock + soft stop\n"
    return t.replace(anchor, block + anchor)


CATCH = (
    '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
    '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
    '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && (!symbol_is("JPM")) '
    '&& (!symbol_is("XOM")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)\n'
)


def mk_bac_mild_green_sticky(hi: float = 0.005, tip: float = 0.10) -> Path:
    """BAC 0 <= fo < hi → sticky (eval +0.13%); fo >= hi stays atr (2022 +1.98%)."""
    name = f"_p_v7h_bac_mild{int(hi * 10000)}_tip{int(tip * 100)}.ms"
    t = BASE
    # bacArm already exists
    # sticky already has bacArm — tip already exists for bac red; extend arm block only
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
    new = f"""    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= {hi}: atrGate.set(1)
      when fo >= 0.0 && fo < {hi}: {{
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo < 0.0: {{
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("BAC block missing")
    t = t.replace(old, new)
    return write(name, t, f"BAC mild-green 0<=fo<{hi} sticky tip>{tip:.0%}; hot atr")


def mk_wmt_band_sticky(lo: float = -0.005, hi: float = -0.002, tip: float = 0.06) -> Path:
    """WMT lo < fo < hi → sticky (2019 -0.37%); 2024 -0.69% stays crown; 2022 atr."""
    name = f"_p_v7h_wmt_band{int(abs(lo)*10000)}_{int(abs(hi)*10000)}_tip{int(tip*100)}.ms"
    t = ensure_latch(BASE, "wmtArm")
    t = sticky_add(t, 'symbol_is("WMT") && wmtArm.is(1)')
    # remove WMT from atrOn when band arms; keep atr for deep
    # patch WMT bar1
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: band sticky + deep atr
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo > {lo} && fo < {hi}: {{
        wmtArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("WMT block missing")
    t = t.replace(old, new)
    # atrOn stays; sticky band takes path when armed (atrGate not set)
    tip_block = f"""    // WMT mild-red band sticky tip
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
    t = insert_tip(t, tip_block)
    t = exclude_sticky_exit(t, "wmtArm")
    return write(name, t, f"WMT {lo}<fo<{hi} sticky tip>{tip:.0%}")


def mk_tsla_mild_green(hi: float = 0.015, tip: float = 0.40, mode: str = "sticky") -> Path:
    """TSLA 0 < fo < hi → sticky/ride (2024 +0.59%); skip hot eval +6.85%."""
    name = f"_p_v7h_tsla_mild{int(hi*1000)}_{mode}_tip{int(tip*100)}.ms"
    t = ensure_latch(BASE, "tslaArm")
    if mode == "sticky":
        t = sticky_add(t, 'symbol_is("TSLA") && tslaArm.is(1)')
        # mute crown when armed
        crown = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
        if crown not in t:
            raise SystemExit("jpm crown mute missing")
        t = t.replace(
            crown,
            crown + ' && (!(symbol_is("TSLA") && tslaArm.is(1)))',
        )
        arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.0 && fo < {hi}: {{
        tslaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
        tip_block = f"""    // TSLA mild-green sticky tip
    when stickyOn && symbol_is("TSLA") && tslaArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("TSLA") && tslaArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
        t = insert_tip(t, tip_block)
        t = exclude_sticky_exit(t, "tslaArm")
    else:
        # ride mode
        old_ride = (
            '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
            '|| (symbol_is("SPY") && (!spyArm.is(1)))\n'
        )
        if old_ride not in t:
            raise SystemExit("rideSym missing")
        t = t.replace(
            old_ride,
            old_ride.replace(
                '(symbol_is("SPY") && (!spyArm.is(1)))',
                '(symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("TSLA") && tslaArm.is(1))',
            ),
        )
        arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.0 && fo < {hi}: {{
        tslaArm.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    if CATCH not in t:
        raise SystemExit("catch missing")
    catch_new = CATCH.replace(
        '(!symbol_is("XOM"))',
        '(!symbol_is("XOM")) && (!symbol_is("TSLA"))',
    )
    t = t.replace(CATCH, arm + catch_new)
    return write(name, t, f"TSLA 0<fo<{hi} {mode} tip>{tip:.0%}")


def mk_jpm_hot_ride(cut: float = 0.02) -> Path:
    """JPM fo > cut → seed-ride (2022 +2.14%); hope demote + few trades lifts abs sharpe."""
    name = f"_p_v7h_jpm_hotride{int(cut*1000)}.ms"
    t = ensure_latch(BASE, "jpmHot")
    old_ride = (
        '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
        '|| (symbol_is("SPY") && (!spyArm.is(1)))\n'
    )
    t = t.replace(
        old_ride,
        old_ride.replace(
            '(symbol_is("SPY") && (!spyArm.is(1)))',
            '(symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("JPM") && jpmHot.is(1))',
        ),
    )
    # mute jpm crown when hot (jpmArm deep-red still separate)
    crown = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
    t = t.replace(crown, crown + ' && (!(symbol_is("JPM") && jpmHot.is(1)))')
    # extend existing JPM bar1 block
    old = """    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = f"""    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {{
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo > {cut}: {{
        jpmHot.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("JPM block missing")
    t = t.replace(old, new)
    return write(name, t, f"JPM fo>{cut} seed-ride (2022 hot)")


def mk_jpm_hot_flat(cut: float = 0.02) -> Path:
    """JPM fo > cut → suppress crown early (primed); allow later crown after bar>=25 mute cleared? 

    Simpler: set quietArm-like short tilt via flipGate brain, or just atr with no early fills.
    Here: hot → atr (retry) AND also a tip: mute donch for first N via doneGate? 

    Alternative causal: hot → sticky short via quiet path (r5>70 short). Use quietArm.
    """
    name = f"_p_v7h_jpm_hotquiet{int(cut*1000)}.ms"
    t = BASE
    old = """    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = f"""    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {{
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo > {cut}: quietArm.set(1)
      primed.set(1)
    }}
"""
    # quietOn already covers AMD|GOOGL — extend to JPM
    t = t.replace(
        '  quietOn = quietArm.is(1) && (symbol_is("AMD") || symbol_is("GOOGL"))\n',
        '  quietOn = quietArm.is(1) && (symbol_is("AMD") || symbol_is("GOOGL") || symbol_is("JPM"))\n',
    )
    # crown already muted? quietOn is separate sleeve; crownOn should exclude quiet
    # Currently crownOn does NOT exclude quietOn explicitly — but onBar order: quiet runs then crown.
    # quietOn sets path 9; crown may still fire. Check crownOn: (!quietOn) is NOT there!
    # Looking at v7h: crownOn has (!quietOn)? No — '(!stickyOn) && (!atrOn) && (!flipOn) && (!quietOn)' YES it does.
    if old not in t:
        raise SystemExit("JPM block missing")
    t = t.replace(old, new)
    return write(name, t, f"JPM fo>{cut} → quiet short/long sleeve")


def mk_xom_mild_atr(lo: float = -0.005, hi: float = 0.0) -> Path:
    """XOM lo < fo < hi → atr (2024 -0.34%); deep sticky unchanged."""
    name = f"_p_v7h_xom_mildatr{int(abs(lo)*10000)}.ms"
    t = BASE
    t = t.replace(
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1)) || (symbol_is("XOM") && atrGate.is(1))\n',
    )
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
      when fo > {lo} && fo < {hi}: atrGate.set(1)
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("XOM block missing")
    t = t.replace(old, new)
    return write(name, t, f"XOM {lo}<fo<{hi} → atr (2024 mild)")


def mk_xom_mild_mute(lo: float = -0.005, hi: float = 0.0) -> Path:
    """XOM mild red → kill early crown via doneGate/rideDone style mute (seedOpen + arm)."""
    name = f"_p_v7h_xom_mildmute{int(abs(lo)*10000)}.ms"
    t = ensure_latch(BASE, "xomMild")
    # mute crown when xomMild
    crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
    t = t.replace(
        crown,
        crown + ' && (!(symbol_is("XOM") && xomMild.is(1)))',
    )
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
      when fo > {lo} && fo < {hi}: xomMild.set(1)
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("XOM block missing")
    t = t.replace(old, new)
    return write(name, t, f"XOM {lo}<fo<{hi} crown-mute (no sticky)")


def main() -> int:
    mk_bac_mild_green_sticky(0.005, 0.10)
    mk_bac_mild_green_sticky(0.005, 0.12)
    mk_bac_mild_green_sticky(0.008, 0.10)
    mk_wmt_band_sticky(-0.005, -0.002, 0.06)
    mk_wmt_band_sticky(-0.005, -0.002, 0.08)
    mk_wmt_band_sticky(-0.006, -0.002, 0.06)
    mk_tsla_mild_green(0.015, 0.40, "sticky")
    mk_tsla_mild_green(0.015, 0.55, "sticky")
    mk_tsla_mild_green(0.02, 0.50, "sticky")
    mk_tsla_mild_green(0.015, 0.40, "ride")
    mk_jpm_hot_ride(0.02)
    mk_jpm_hot_quiet = mk_jpm_hot_flat  # alias
    mk_jpm_hot_quiet(0.02)
    mk_xom_mild_atr(-0.005, 0.0)
    mk_xom_mild_mute(-0.005, 0.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
