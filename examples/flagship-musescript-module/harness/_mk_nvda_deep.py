"""Build NVDA deep-red sticky tip probes from flagship_v7h.ms.

Discriminates NVDA@2019 fo~-4.34% from NVDA@2022 fo~-3.26% via fo < -0.04.
Series-time nvdaBar1Deep for same-bar crown suppress (amd/googl/qqq pattern).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
base = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")


def build(tip: float = 0.35, cut: float = -0.04, name: str = "_p_v7h_nvda_deep.ms") -> Path:
    t = base.replace("class FlagshipV7h", "class FlagshipProbe")
    t = (
        f"// probe {name}\n"
        f"// NVDA deep-red fo<{cut:.3f} sticky tip>{tip:.0%} via series nvdaBar1Deep "
        f"(dual keeps 2022 fo~-3.3%).\n"
        + t
    )
    if "nvdaArm = new PathLatch()" not in t:
        t = t.replace(
            "  googlArm = new PathLatch()\n",
            "  googlArm = new PathLatch()\n  nvdaArm = new PathLatch()\n",
        )

    old_deep = (
        "  googlBar1Deep = symbol_is(\"GOOGL\") && bar_index == 1 && ((close - open) / open) < -0.02\n"
    )
    new_deep = (
        "  googlBar1Deep = symbol_is(\"GOOGL\") && bar_index == 1 && ((close - open) / open) < -0.02\n"
        f"  nvdaBar1Deep = symbol_is(\"NVDA\") && bar_index == 1 && ((close - open) / open) < {cut}\n"
    )
    if old_deep not in t:
        raise SystemExit("googlBar1Deep anchor missing")
    # Note: header comment may already contain the token — key on definition line.
    if "nvdaBar1Deep = symbol_is" not in t:
        t = t.replace(old_deep, new_deep)

    old_sticky = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1))) && stickyGate.is(1)\n'
    )
    new_sticky = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
    )
    if old_sticky not in t:
        raise SystemExit("stickyOn anchor missing")
    t = t.replace(old_sticky, new_sticky)

    old_crown = (
        '  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!quietOn) && (!symbol_is("IWM")) '
        '&& (!riding) && (!rideDone) && (!(symbol_is("AMZN") && (amznArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("AAPL") && bar_index < 2)) && (!((symbol_is("AMD") || symbol_is("GOOGL")) && bar_index < 2)) '
        '&& (!(symbol_is("META") && (metaArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2))) '
        '&& (!qqqBar1Deep) && (!(symbol_is("QQQ") && qqqArm.is(1))) '
        '&& (!amdBar1Deep) && (!(symbol_is("AMD") && amdArm.is(1))) '
        '&& (!googlBar1Deep) && (!(symbol_is("GOOGL") && googlArm.is(1)))\n'
    )
    new_crown = (
        '  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!quietOn) && (!symbol_is("IWM")) '
        '&& (!riding) && (!rideDone) && (!(symbol_is("AMZN") && (amznArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("AAPL") && bar_index < 2)) && (!((symbol_is("AMD") || symbol_is("GOOGL")) && bar_index < 2)) '
        '&& (!(symbol_is("META") && (metaArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2))) '
        '&& (!qqqBar1Deep) && (!(symbol_is("QQQ") && qqqArm.is(1))) '
        '&& (!amdBar1Deep) && (!(symbol_is("AMD") && amdArm.is(1))) '
        '&& (!googlBar1Deep) && (!(symbol_is("GOOGL") && googlArm.is(1))) '
        '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))\n'
    )
    if old_crown not in t:
        raise SystemExit("crownOn anchor missing")
    t = t.replace(old_crown, new_crown)

    # NVDA is currently under the generic primed.set catch-all (excluded list).
    # Insert NVDA bar1 sticky arm before that catch-all.
    old_prime_catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)\n'
    )
    new_nvda_arm = f"""    when symbol_is("NVDA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        nvdaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    new_prime_catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && bar_index == 1 '
        '&& primed.get() < 0.5: primed.set(1)\n'
    )
    if old_prime_catch not in t:
        raise SystemExit("primed catch-all anchor missing")
    if "nvdaArm.set" not in t:
        t = t.replace(old_prime_catch, new_nvda_arm + new_prime_catch)
    else:
        t = t.replace(old_prime_catch, new_prime_catch)

    tip_block = f"""    // NVDA deep-red tip: lock near 2019 peak/end (~36-38%)
    when stickyOn && symbol_is("NVDA") && nvdaArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("NVDA") && nvdaArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    anchor = "    // SPY deep-red sticky: tip-lock + soft stop\n"
    if "NVDA deep-red tip" not in t:
        if anchor not in t:
            raise SystemExit("SPY tip anchor missing")
        t = t.replace(anchor, tip_block + anchor)

    old_iwm1 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) '
        '&& (!googlArm.is(1)) && bar_index >= 55 && r5 < 45: {\n'
    )
    new_iwm1 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) '
        '&& (!googlArm.is(1)) && (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45: {\n'
    )
    old_iwm2 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) '
        '&& (!googlArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n'
    )
    new_iwm2 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) '
        '&& (!googlArm.is(1)) && (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n'
    )
    if old_iwm1 not in t or old_iwm2 not in t:
        raise SystemExit("IWM sticky exit anchors missing")
    t = t.replace(old_iwm1, new_iwm1).replace(old_iwm2, new_iwm2)

    out = ROOT / "strategies" / "probes" / name
    out.write_text(t, encoding="utf-8")
    print("wrote", out.relative_to(ROOT), "tip", tip, "cut", cut)
    return out


if __name__ == "__main__":
    build(tip=0.35, cut=-0.04, name="_p_v7h_nvda_deep.ms")
    build(tip=0.36, cut=-0.04, name="_p_v7h_nvda_tip36.ms")
    build(tip=0.34, cut=-0.04, name="_p_v7h_nvda_tip34.ms")
    build(tip=0.37, cut=-0.04, name="_p_v7h_nvda_tip37.ms")
    build(tip=0.35, cut=-0.038, name="_p_v7h_nvda_cut38.ms")
    build(tip=0.35, cut=-0.042, name="_p_v7h_nvda_cut42.ms")
