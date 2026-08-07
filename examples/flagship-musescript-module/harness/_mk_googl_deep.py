"""Build GOOGL deep-red sticky tip probe on top of v7h (AMD DNA already folded)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
base = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")

TIP = 0.15
CUT = -0.02


def build(tip: float = TIP, cut: float = CUT, name: str = "_p_v7h_googl_deep.ms") -> Path:
    t = base.replace("class FlagshipV7h", "class FlagshipProbe")
    t = (
        f"// probe {name}\n"
        f"// GOOGL deep-red fo<{cut:.3f} sticky tip>{tip:.0%} via series googlBar1Deep.\n"
        + t
    )
    t = t.replace(
        "  amdArm = new PathLatch()\n",
        "  amdArm = new PathLatch()\n  googlArm = new PathLatch()\n",
    )

    old_deep = (
        "  amdBar1Deep = symbol_is(\"AMD\") && bar_index == 1 && ((close - open) / open) < -0.05\n"
    )
    new_deep = (
        "  amdBar1Deep = symbol_is(\"AMD\") && bar_index == 1 && ((close - open) / open) < -0.05\n"
        f"  googlBar1Deep = symbol_is(\"GOOGL\") && bar_index == 1 && ((close - open) / open) < {cut}\n"
    )
    if old_deep not in t:
        raise SystemExit("amdBar1Deep missing")
    t = t.replace(old_deep, new_deep)

    old_sticky = (
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1))) && stickyGate.is(1)\n'
    )
    new_sticky = (
        '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
        '(symbol_is("GOOGL") && googlArm.is(1))) && stickyGate.is(1)\n'
    )
    if old_sticky not in t:
        raise SystemExit("stickyOn amd tail missing")
    t = t.replace(old_sticky, new_sticky)

    old_crown_tail = (
        "&& (!amdBar1Deep) && (!(symbol_is(\"AMD\") && amdArm.is(1)))\n"
    )
    new_crown_tail = (
        "&& (!amdBar1Deep) && (!(symbol_is(\"AMD\") && amdArm.is(1))) "
        "&& (!googlBar1Deep) && (!(symbol_is(\"GOOGL\") && googlArm.is(1)))\n"
    )
    if old_crown_tail not in t:
        raise SystemExit("crown amd tail missing")
    t = t.replace(old_crown_tail, new_crown_tail)

    old_googl = """    when symbol_is("GOOGL") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }"""
    new_googl = f"""    when symbol_is("GOOGL") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < {cut}: {{
        googlArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }}"""
    if old_googl not in t:
        raise SystemExit("GOOGL prime missing")
    t = t.replace(old_googl, new_googl)

    tip_block = f"""    // GOOGL deep-red tip: lock near 2019 peak/end (~14-18%)
    when stickyOn && symbol_is("GOOGL") && googlArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("GOOGL") && googlArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    anchor = "    // SPY deep-red sticky: tip-lock + soft stop\n"
    if "GOOGL deep-red tip" not in t:
        t = t.replace(anchor, tip_block + anchor)

    # exclude from IWM sticky exits (amd already excluded)
    for old, new in [
        (
            "&& (!amdArm.is(1)) && bar_index >= 55 && r5 < 45: {\n",
            "&& (!amdArm.is(1)) && (!googlArm.is(1)) && bar_index >= 55 && r5 < 45: {\n",
        ),
        (
            "&& (!amdArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n",
            "&& (!amdArm.is(1)) && (!googlArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {\n",
        ),
    ]:
        if old not in t:
            raise SystemExit(f"iwm exit missing: {old[:40]}")
        t = t.replace(old, new)

    out = ROOT / "strategies" / "probes" / name
    out.write_text(t, encoding="utf-8")
    print("wrote", out.name, "tip", tip, "cut", cut)
    return out


if __name__ == "__main__":
    build(0.15, -0.02, "_p_v7h_googl_deep.ms")
    build(0.14, -0.02, "_p_v7h_googl_tip14.ms")
    build(0.16, -0.02, "_p_v7h_googl_tip16.ms")
    build(0.15, -0.015, "_p_v7h_googl_cut15.ms")
