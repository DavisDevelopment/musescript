"""Build AMD deep-red sticky tip probes from flagship_v7h.ms.

Discriminates AMD@2019 fo~-7.4% from AMD@2022 fo~-4.4% via fo < -0.05.
Series-time amdBar1Deep for same-bar crown suppress (qqqBar1Deep pattern).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
base = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")

TIP = 0.45  # near 2019 peak~51% / end~43%; beat BH giveback


def build(tip: float = TIP, cut: float = -0.05, name: str = "_p_v7h_amd_deep.ms") -> Path:
    t = base.replace("class FlagshipV7h", "class FlagshipProbe")
    t = (
        f"// probe {name}\n"
        f"// AMD deep-red fo<{cut:.3f} sticky tip>{tip:.0%} via series amdBar1Deep (dual keeps mild-red 2022).\n"
        + t
    )
    t = t.replace(
        "  qqqArm = new PathLatch()\n",
        "  qqqArm = new PathLatch()\n  amdArm = new PathLatch()\n",
    )

    old_deep = (
        "  qqqBar1Deep = symbol_is(\"QQQ\") && bar_index == 1 && ((close - open) / open) < -0.015\n"
    )
    new_deep = (
        "  qqqBar1Deep = symbol_is(\"QQQ\") && bar_index == 1 && ((close - open) / open) < -0.015\n"
        f"  amdBar1Deep = symbol_is(\"AMD\") && bar_index == 1 && ((close - open) / open) < {cut}\n"
    )
    if old_deep not in t:
        raise SystemExit("qqqBar1Deep anchor missing")
    t = t.replace(old_deep, new_deep)

    old_sticky = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1))) && stickyGate.is(1)\n'
    )
    new_sticky = (
        '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
        '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
        '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1))) && stickyGate.is(1)\n'
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
        '&& (!qqqBar1Deep) && (!(symbol_is("QQQ") && qqqArm.is(1)))\n'
    )
    new_crown = (
        '  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!quietOn) && (!symbol_is("IWM")) '
        '&& (!riding) && (!rideDone) && (!(symbol_is("AMZN") && (amznArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("AAPL") && bar_index < 2)) && (!((symbol_is("AMD") || symbol_is("GOOGL")) && bar_index < 2)) '
        '&& (!(symbol_is("META") && (metaArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2))) '
        '&& (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2))) '
        '&& (!qqqBar1Deep) && (!(symbol_is("QQQ") && qqqArm.is(1))) '
        '&& (!amdBar1Deep) && (!(symbol_is("AMD") && amdArm.is(1)))\n'
    )
    if old_crown not in t:
        raise SystemExit("crownOn anchor missing")
    t = t.replace(old_crown, new_crown)

    old_amd = """    when (symbol_is("AMD") || symbol_is("GOOGL")) && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }"""
    new_amd = f"""    when symbol_is("AMD") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        amdArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }}
    when symbol_is("GOOGL") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }}"""
    if old_amd not in t:
        raise SystemExit("AMD/GOOGL prime anchor missing")
    t = t.replace(old_amd, new_amd)

    # tip-lock + soft stop (QQQ pattern); exclude from IWM-style sticky exits
    tip_block = f"""    // AMD deep-red tip: lock near 2019 peak/end (~43-51%)
    when stickyOn && symbol_is("AMD") && amdArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("AMD") && amdArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    anchor = "    // SPY deep-red sticky: tip-lock + soft stop\n"
    if tip_block.strip()[:40] not in t:
        if anchor not in t:
            raise SystemExit("SPY tip anchor missing")
        t = t.replace(anchor, tip_block + anchor)

    old_iwm1 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && bar_index >= 55 && r5 < 45: {\n'
    )
    new_iwm1 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) && bar_index >= 55 && r5 < 45: {\n'
    )
    old_iwm2 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n'
    )
    new_iwm2 = (
        '    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) '
        '&& (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n'
    )
    if old_iwm1 not in t or old_iwm2 not in t:
        raise SystemExit("IWM sticky exit anchors missing")
    t = t.replace(old_iwm1, new_iwm1).replace(old_iwm2, new_iwm2)

    out = ROOT / "strategies" / "probes" / name
    out.write_text(t, encoding="utf-8")
    print("wrote", out.relative_to(ROOT), "tip", tip, "cut", cut)
    return out


if __name__ == "__main__":
    build(tip=0.45, cut=-0.05, name="_p_v7h_amd_deep.ms")
    build(tip=0.43, cut=-0.05, name="_p_v7h_amd_tip43.ms")
    build(tip=0.48, cut=-0.05, name="_p_v7h_amd_tip48.ms")
    build(tip=0.40, cut=-0.05, name="_p_v7h_amd_tip40.ms")
    build(tip=0.45, cut=-0.055, name="_p_v7h_amd_cut55.ms")
    build(tip=0.45, cut=-0.06, name="_p_v7h_amd_cut60.ms")
