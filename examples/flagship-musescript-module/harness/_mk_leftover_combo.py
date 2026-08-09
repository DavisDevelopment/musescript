"""Combine XOM cut15 sticky + BAC red sticky onto v7h; also JPM tip sweep."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
base = (ROOT / "strategies/flagship_v7h.ms").read_text(encoding="utf-8")


def write(name: str, t: str, hdr: str) -> Path:
    t = t.replace("class FlagshipV7h", "class FlagshipProbe")
    p = ROOT / "strategies/probes" / name
    p.write_text(f"// probe {name}\n// {hdr}\n" + t, encoding="utf-8")
    print("wrote", p.relative_to(ROOT))
    return p


CATCH = (
    '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
    '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
    '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && bar_index == 1 '
    '&& primed.get() < 0.5: primed.set(1)\n'
)
STICKY = (
    '  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || '
    '(symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || '
    '(symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || '
    '(symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || '
    '(symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1))) && stickyGate.is(1)\n'
)


def graft_xom(t: str, cut: float = -0.015, tip: float = 0.15) -> str:
    if "xomArm = new PathLatch()" not in t:
        t = t.replace("  nvdaArm = new PathLatch()\n", "  nvdaArm = new PathLatch()\n  xomArm = new PathLatch()\n")
    if 'symbol_is("XOM") && xomArm.is(1)' not in t.split("stickyOn")[1][:400]:
        t = t.replace(
            STICKY if STICKY in t else "STICKY_MISSING",
            STICKY.replace(
                '(symbol_is("NVDA") && nvdaArm.is(1)))',
                '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("XOM") && xomArm.is(1)))',
            ),
        )
    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    if "xomArm.is(1) || bar_index < 2" not in t:
        t = t.replace(
            crown_bit,
            crown_bit + ' && (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))',
        )
    if "xomArm.set" not in t:
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
        catch = CATCH
        if '(!symbol_is("XOM"))' not in t:
            catch_new = catch.replace('(!symbol_is("NVDA"))', '(!symbol_is("NVDA")) && (!symbol_is("XOM"))')
        else:
            catch_new = catch
        # catch may already be modified
        if catch in t:
            t = t.replace(catch, arm + catch_new)
        else:
            # already has XOM excluded maybe from prior grafts — find NVDA-excluded catch
            raise SystemExit("catch for XOM missing")
    if "XOM deep-red sticky tip" not in t:
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
    if "(!xomArm.is(1))" not in t:
        t = t.replace(
            '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
            '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 55 && r5 < 45:',
        )
        t = t.replace(
            '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            '&& (!nvdaArm.is(1)) && (!xomArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
        )
    return t


def graft_bac_red(t: str, tip: float = 0.10) -> str:
    if "bacArm = new PathLatch()" not in t:
        t = t.replace("  nvdaArm = new PathLatch()\n", "  nvdaArm = new PathLatch()\n  bacArm = new PathLatch()\n")
    # sticky may already include XOM
    if '(symbol_is("BAC") && bacArm.is(1))' not in t:
        # find stickyOn line and extend
        import re

        m = re.search(r"  stickyOn = .*&& stickyGate\.is\(1\)\n", t)
        if not m:
            raise SystemExit("stickyOn line missing")
        line = m.group(0)
        if '(symbol_is("BAC") && bacArm.is(1))' not in line:
            newline = line.replace(
                ") && stickyGate.is(1)",
                ' || (symbol_is("BAC") && bacArm.is(1))) && stickyGate.is(1)',
            )
            # careful: above may break parens. Better replace last nvda/xom clause end.
            if '(symbol_is("XOM") && xomArm.is(1)))' in line:
                newline = line.replace(
                    '(symbol_is("XOM") && xomArm.is(1)))',
                    '(symbol_is("XOM") && xomArm.is(1)) || (symbol_is("BAC") && bacArm.is(1)))',
                )
            elif '(symbol_is("NVDA") && nvdaArm.is(1)))' in line:
                newline = line.replace(
                    '(symbol_is("NVDA") && nvdaArm.is(1)))',
                    '(symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("BAC") && bacArm.is(1)))',
                )
            t = t.replace(line, newline)
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
    if old_bac not in t:
        raise SystemExit("BAC block missing or already patched")
    t = t.replace(old_bac, new_bac)
    if "BAC red sticky tip" not in t:
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
    # exclude bac from iwm-default sticky exits
    if "(!bacArm.is(1))" not in t:
        t = t.replace("(!xomArm.is(1)) && bar_index >= 55", "(!xomArm.is(1)) && (!bacArm.is(1)) && bar_index >= 55")
        t = t.replace(
            "(!xomArm.is(1)) && bar_index >= 14 && unrealized_pnl",
            "(!xomArm.is(1)) && (!bacArm.is(1)) && bar_index >= 14 && unrealized_pnl",
        )
        if "(!bacArm.is(1))" not in t:
            t = t.replace(
                '&& (!nvdaArm.is(1)) && bar_index >= 55 && r5 < 45:',
                '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 55 && r5 < 45:',
            )
            t = t.replace(
                '&& (!nvdaArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                '&& (!nvdaArm.is(1)) && (!bacArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
            )
    return t


def graft_jpm(t: str, cut: float = -0.015, tip: float = 0.08) -> str:
    if "jpmArm = new PathLatch()" not in t:
        t = t.replace("  nvdaArm = new PathLatch()\n", "  nvdaArm = new PathLatch()\n  jpmArm = new PathLatch()\n")
    import re

    m = re.search(r"  stickyOn = .*&& stickyGate\.is\(1\)\n", t)
    line = m.group(0)
    if '(symbol_is("JPM") && jpmArm.is(1))' not in line:
        # insert before closing ))
        newline = line.replace(
            ") && stickyGate.is(1)",
            ' || (symbol_is("JPM") && jpmArm.is(1))) && stickyGate.is(1)',
        )
        # fix double paren: previous ends with )))
        # Actually replace last known arm
        for key in [
            '(symbol_is("BAC") && bacArm.is(1)))',
            '(symbol_is("XOM") && xomArm.is(1)))',
            '(symbol_is("NVDA") && nvdaArm.is(1)))',
        ]:
            if key in line:
                newline = line.replace(
                    key,
                    key[:-1] + ' || (symbol_is("JPM") && jpmArm.is(1)))',
                )
                break
        t = t.replace(line, newline)
    crown_bit = '&& (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1)))'
    if 'symbol_is("JPM") && (jpmArm.is(1)' not in t:
        # may already have XOM crown addendum
        if 'symbol_is("XOM") && (xomArm.is(1)' in t:
            t = t.replace(
                '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))',
                '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2))) && (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))',
            )
        else:
            t = t.replace(
                crown_bit,
                crown_bit + ' && (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))',
            )
    if "jpmArm.set" not in t:
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
        # find current catch
        import re as _re

        cm = _re.search(
            r'    when \(!symbol_is\("IWM"\)\).*primed\.set\(1\)\n',
            t,
        )
        if not cm:
            raise SystemExit("catch missing for jpm")
        catch = cm.group(0)
        if '(!symbol_is("JPM"))' not in catch:
            catch_new = catch.replace(
                '(!symbol_is("NVDA"))',
                '(!symbol_is("NVDA")) && (!symbol_is("JPM"))',
            )
            if '(!symbol_is("XOM"))' in catch and '(!symbol_is("JPM"))' not in catch_new:
                catch_new = catch.replace(
                    '(!symbol_is("XOM"))',
                    '(!symbol_is("XOM")) && (!symbol_is("JPM"))',
                )
            t = t.replace(catch, arm + catch_new)
        else:
            t = t.replace(catch, arm + catch)
    if "JPM deep-red sticky tip" not in t:
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
        t = t.replace(
            "    // SPY deep-red sticky: tip-lock + soft stop\n",
            tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n",
        )
    if "(!jpmArm.is(1))" not in t:
        # append to existing exclude chain
        for token in ["(!bacArm.is(1))", "(!xomArm.is(1))", "(!nvdaArm.is(1))"]:
            if token + " && bar_index >= 55" in t:
                t = t.replace(
                    token + " && bar_index >= 55",
                    token + " && (!jpmArm.is(1)) && bar_index >= 55",
                )
                t = t.replace(
                    token + " && bar_index >= 14",
                    token + " && (!jpmArm.is(1)) && bar_index >= 14",
                )
                break
    return t


def main() -> int:
    # combo xom+bac
    t = graft_bac_red(graft_xom(base, -0.015, 0.15), 0.10)
    write("_p_v7h_xom_bac_combo.ms", t, "XOM fo<-1.5% tip15 + BAC fo<0 tip10")

    # jpm tip sweeps on base
    for tip in [0.06, 0.07, 0.075, 0.08, 0.085, 0.09, 0.10]:
        tj = graft_jpm(base, -0.015, tip)
        write(f"_p_v7h_jpm_tip{int(tip*1000)}.ms", tj, f"JPM fo<-1.5% sticky tip>{tip:.1%}")

    # combo + jpm tip08
    tj2 = graft_jpm(graft_bac_red(graft_xom(base, -0.015, 0.15), 0.10), -0.015, 0.08)
    write("_p_v7h_xom_bac_jpm.ms", tj2, "XOM+BAC+JPM tip08 combo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
