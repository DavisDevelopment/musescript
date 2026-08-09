"""Surgical leftover probes from flagship_v7h.ms (JPM/XOM/TSLA/BAC/WMT).

bar1 fo (bar_index==1 == csv i1):
  JPM  eval -2.55% | 2022 +2.14% | 2019 -1.55% | 2024 +0.10%
  XOM  eval +0.28% | 2022 +2.81% | 2019 -1.97% | 2024 -0.34%
  TSLA eval +6.85% | 2022 -3.36% | 2019 -2.16% | 2024 +0.59%
  BAC  eval +0.13% | 2022 +1.98% | 2019 -1.52% | 2024 -0.05%
  WMT  eval +0.10% | 2022 -1.42% | 2019 -0.37% | 2024 -0.69%
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")
OUT = ROOT / "strategies/probes"


def _write(name: str, body: str, header: str) -> Path:
    t = body.replace("class FlagshipV7h", "class FlagshipProbe")
    t = f"// probe {name}\n// {header}\n" + t
    path = OUT / name
    path.write_text(t, encoding="utf-8")
    print("wrote", path.relative_to(ROOT))
    return path


def _ensure_latch(t: str, name: str, after: str = "nvdaArm = new PathLatch()") -> str:
    line = f"  {name} = new PathLatch()"
    if line in t:
        return t
    anchor = f"  {after}\n"
    if anchor not in t:
        raise SystemExit(f"missing latch anchor {after}")
    return t.replace(anchor, anchor + f"  {name} = new PathLatch()\n")


CATCH = (
    '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
    '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
    '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && bar_index == 1 '
    '&& primed.get() < 0.5: primed.set(1)\n'
)


def mk_jpm_deep_sticky(cut: float = -0.015, tip: float = 0.12) -> Path:
    """JPM fo < cut → sticky tip-lock. Hits eval (-2.55%) + 2019 (-1.55%); skips green 2022/2024."""
    name = f"_p_v7h_jpm_cut{int(abs(cut)*1000)}.ms"
    t = BASE
    t = _ensure_latch(t, "jpmArm")
    sticky_old = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
    )
    sticky_new = sticky_old.replace(
        '(symbol_is("NVDA") && nvdaArm.is(1)))',
        '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("JPM") && jpmArm.is(1)))',
    )
    if sticky_old not in t:
        raise SystemExit("stickyOn missing")
    t = t.replace(sticky_old, sticky_new)

    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    if crown_bit not in t:
        raise SystemExit("crown nvda bit missing")
    t = t.replace(
        crown_bit,
        crown_bit + ' && (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))',
    )

    arm = f"""    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    catch_new = CATCH.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("JPM"))')
    if CATCH not in t:
        raise SystemExit("catch missing")
    t = t.replace(CATCH, arm + catch_new)

    tip_block = f"""    // JPM deep-red sticky tip
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    anchor = "    // SPY deep-red sticky: tip-lock + soft stop\n"
    t = t.replace(anchor, tip_block + anchor)

    for old, new in [
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
            '&& (!nvdaArm.is(1)) && (!jpmArm.is(1)) && bar_index >= 55 && r5 < 45:',
        ),
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            '&& (!nvdaArm.is(1)) && (!jpmArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        ),
    ]:
        if old not in t:
            raise SystemExit(f"iwm exclude missing: {old}")
        t = t.replace(old, new)

    return _write(name, t, f"JPM fo<{cut} sticky tip>{tip:.0%}")


def mk_tsla_hot_demote(cut: float = 0.04) -> Path:
    """TSLA bar1 fo > cut → seed-ride (or quiet). Hits eval (+6.85%) only among leftovers."""
    name = f"_p_v7h_tsla_hot{int(cut*1000)}.ms"
    t = BASE
    # Treat hot TSLA as rideSym seed (like green SPY/QQQ) — suppress crown churn.
    old_ride = (
        '  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) '
        '|| (symbol_is("SPY") && (!spyArm.is(1)))\n'
    )
    # Keep rideSym expression; add series-time deep-green flag + arm.
    t = _ensure_latch(t, "tslaHot")
    deep = (
        "  nvdaBar1Deep = symbol_is(\"NVDA\") && bar_index == 1 && ((close - open) / open) < -0.04\n"
    )
    deep_new = deep + f"  tslaBar1Hot = symbol_is(\"TSLA\") && bar_index == 1 && ((close - open) / open) > {cut}\n"
    if deep not in t:
        raise SystemExit("nvdaBar1Deep def missing")
    t = t.replace(deep, deep_new)

    # Mute crown while tsla hot primed without ride yet
    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    t = t.replace(
        crown_bit,
        crown_bit + " && (!tslaBar1Hot) && (!(symbol_is(\"TSLA\") && tslaHot.is(1)))",
    )

    if old_ride not in t:
        raise SystemExit("rideSym missing")
    t = t.replace(
        old_ride,
        old_ride.replace(
            '(symbol_is("SPY") && (!spyArm.is(1)))',
            '(symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("TSLA") && tslaHot.is(1))',
        ),
    )

    arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > {cut}: {{
        tslaHot.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    catch_new = CATCH.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("TSLA"))')
    t = t.replace(CATCH, arm + catch_new)
    return _write(name, t, f"TSLA fo>{cut} seed-ride (eval hot +6.85%)")


def mk_tsla_deep_sticky(cut: float = -0.025, tip: float = 0.25) -> Path:
    """TSLA fo < cut sticky. Would hit 2019 (-2.16%) and 2022 (-3.36%) — 2022 already P; tip must preserve."""
    name = f"_p_v7h_tsla_cut{int(abs(cut)*1000)}.ms"
    t = BASE
    t = _ensure_latch(t, "tslaArm")
    sticky_old = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
    )
    t = t.replace(
        sticky_old,
        sticky_old.replace(
            '(symbol_is("NVDA") && nvdaArm.is(1)))',
            '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("TSLA") && tslaArm.is(1)))',
        ),
    )
    deep = (
        "  nvdaBar1Deep = symbol_is(\"NVDA\") && bar_index == 1 && ((close - open) / open) < -0.04\n"
    )
    t = t.replace(
        deep,
        deep + f"  tslaBar1Deep = symbol_is(\"TSLA\") && bar_index == 1 && ((close - open) / open) < {cut}\n",
    )
    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    t = t.replace(
        crown_bit,
        crown_bit + ' && (!tslaBar1Deep) && (!(symbol_is("TSLA") && tslaArm.is(1)))',
    )
    arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        tslaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    catch_new = CATCH.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("TSLA"))')
    t = t.replace(CATCH, arm + catch_new)
    tip_block = f"""    // TSLA deep-red sticky tip
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
    t = t.replace("    // SPY deep-red sticky: tip-lock + soft stop\n", tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n")
    for old, new in [
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
            '&& (!nvdaArm.is(1)) && (!tslaArm.is(1)) && bar_index >= 55 && r5 < 45:',
        ),
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            '&& (!nvdaArm.is(1)) && (!tslaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        ),
    ]:
        t = t.replace(old, new)
    return _write(name, t, f"TSLA fo<{cut} sticky tip>{tip:.0%}")


def mk_xom_red_sticky(cut: float = -0.015, tip: float = 0.15) -> Path:
    """XOM fo < cut sticky. Hits 2019 (-1.97%); skips eval green / 2024 mild -0.34% / 2022 green."""
    name = f"_p_v7h_xom_cut{int(abs(cut)*1000)}.ms"
    t = BASE
    t = _ensure_latch(t, "xomArm")
    sticky_old = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
    )
    t = t.replace(
        sticky_old,
        sticky_old.replace(
            '(symbol_is("NVDA") && nvdaArm.is(1)))',
            '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("XOM") && xomArm.is(1)))',
        ),
    )
    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    t = t.replace(
        crown_bit,
        crown_bit + ' && (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))',
    )
    arm = f"""    when symbol_is("XOM") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        xomArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    catch_new = CATCH.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("XOM"))')
    t = t.replace(CATCH, arm + catch_new)
    tip_block = f"""    // XOM deep-red sticky tip
    when stickyOn && symbol_is("XOM") && xomArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("XOM") && xomArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    t = t.replace("    // SPY deep-red sticky: tip-lock + soft stop\n", tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n")
    for old, new in [
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
            '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 55 && r5 < 45:',
        ),
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        ),
    ]:
        t = t.replace(old, new)
    return _write(name, t, f"XOM fo<{cut} sticky tip>{tip:.0%}")


def mk_bac_always_sticky(tip: float = 0.10) -> Path:
    """BAC always bar1 sticky (override green→atr). Toward BH on eval/2024."""
    name = f"_p_v7h_bac_sticky{int(tip*100)}.ms"
    t = BASE
    t = _ensure_latch(t, "bacArm")
    # Remove BAC from atrOn
    t = t.replace(
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
    )
    sticky_old = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
    )
    t = t.replace(
        sticky_old,
        sticky_old.replace(
            '(symbol_is("NVDA") && nvdaArm.is(1)))',
            '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("BAC") && bacArm.is(1)))',
        ),
    )
    old_bac = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo >= 0.0: atrGate.set(1)
      primed.set(1)
    }
"""
    new_bac = f"""    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      bacArm.set(1)
      stickyGate.set(1)
      path.set(5)
      tickFill()
      long()
      primed.set(1)
    }}
"""
    if old_bac not in t:
        raise SystemExit("BAC arm missing")
    t = t.replace(old_bac, new_bac)
    tip_block = f"""    // BAC sticky tip
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    t = t.replace("    // SPY deep-red sticky: tip-lock + soft stop\n", tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n")
    for old, new in [
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
            '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 55 && r5 < 45:',
        ),
        (
            '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        ),
    ]:
        t = t.replace(old, new)
    return _write(name, t, f"BAC always sticky tip>{tip:.0%}")


def mk_wmt_mild_atr(cut: float = -0.003) -> Path:
    """Widen WMT atr to fo < cut. Hits 2019 (-0.37%) and 2024 (-0.69%) — 2024 currently P crown — risk."""
    name = f"_p_v7h_wmt_atr{int(abs(cut)*10000)}.ms"
    t = BASE
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: widen atr fo < {cut}
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo < {cut}: atrGate.set(1)
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("WMT block missing")
    t = t.replace(old, new)
    return _write(name, t, f"WMT atr fo<{cut}")


def mk_jpm_hot_atr(cut: float = 0.02) -> Path:
    """JPM fo > cut → atr path. Hits 2022 (+2.14%); skips others."""
    name = f"_p_v7h_jpm_hot{int(cut*1000)}.ms"
    t = BASE
    t = t.replace(
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1)) || (symbol_is("JPM") && atrGate.is(1))\n',
    )
    arm = f"""    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo > {cut}: atrGate.set(1)
      primed.set(1)
    }}
"""
    catch_new = CATCH.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("JPM"))')
    t = t.replace(CATCH, arm + catch_new)
    return _write(name, t, f"JPM fo>{cut} → atr (2022 hot)")


def main() -> int:
    mk_jpm_deep_sticky(-0.015, 0.12)
    mk_jpm_deep_sticky(-0.02, 0.10)
    mk_jpm_hot_atr(0.02)
    mk_tsla_hot_demote(0.04)
    mk_tsla_hot_demote(0.05)
    mk_tsla_deep_sticky(-0.025, 0.25)
    mk_tsla_deep_sticky(-0.03, 0.20)
    mk_xom_red_sticky(-0.015, 0.15)
    mk_xom_red_sticky(-0.01, 0.12)
    mk_bac_always_sticky(0.10)
    mk_bac_always_sticky(0.15)
    mk_wmt_mild_atr(-0.003)
    mk_wmt_mild_atr(0.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
