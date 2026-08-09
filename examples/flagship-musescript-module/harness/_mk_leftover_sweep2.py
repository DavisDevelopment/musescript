"""Tip-sweep XOM cut15 + BAC red-only sticky probes."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mk", ROOT / "harness/_mk_leftover_probes.py")
mk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mk)

# Rename tip into filename by patching writer for xom tip variants
base = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")


def write(name: str, t: str, hdr: str) -> None:
    t = t.replace("class FlagshipV7h", "class FlagshipProbe")
    p = ROOT / "strategies/probes" / name
    p.write_text(f"// probe {name}\n// {hdr}\n" + t, encoding="utf-8")
    print("wrote", p.relative_to(ROOT))


for tip in [0.08, 0.10, 0.12, 0.15, 0.18, 0.22, 0.30, 0.40]:
    # rebuild with distinct names
    t = base
    t = t.replace("  nvdaArm = new PathLatch()\n", "  nvdaArm = new PathLatch()\n  xomArm = new PathLatch()\n")
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
    cut = -0.015
    catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && bar_index == 1 '
        '&& primed.get() < 0.5: primed.set(1)\n'
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
    catch_new = catch.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("XOM"))')
    t = t.replace(catch, arm + catch_new)
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
    t = t.replace(
        "    // SPY deep-red sticky: tip-lock + soft stop\n",
        tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n",
    )
    t = t.replace(
        '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
        '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 55 && r5 < 45:',
    )
    t = t.replace(
        '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
    )
    write(f"_p_v7h_xom_cut15_tip{int(tip*100)}.ms", t, f"XOM fo<{cut} sticky tip>{tip:.0%}")


for tip in [0.08, 0.10, 0.12, 0.15, 0.20]:
    t = base
    t = t.replace("  nvdaArm = new PathLatch()\n", "  nvdaArm = new PathLatch()\n  bacArm = new PathLatch()\n")
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
    new_bac = """    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
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
    t = t.replace(old_bac, new_bac)
    tip_block = f"""    // BAC red sticky tip
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
    t = t.replace(
        "    // SPY deep-red sticky: tip-lock + soft stop\n",
        tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n",
    )
    t = t.replace(
        '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
        '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 55 && r5 < 45:',
    )
    t = t.replace(
        '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
    )
    write(f"_p_v7h_bac_red{int(tip*100)}.ms", t, f"BAC fo<0 sticky tip>{tip:.0%}; green atr")

print("done")
