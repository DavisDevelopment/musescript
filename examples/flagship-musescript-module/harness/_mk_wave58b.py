"""BAC crown-seal after sticky tip (kill post-tip crown reclaim). XOM abs-sharpe nudges."""
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


def bac_mild_sticky_base(t: str, tip: float, soft: float) -> str:
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
      when fo >= 0.0 && fo < 0.004: {{
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      when fo >= 0.004: atrGate.set(1)
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
    t = t.replace(old, new)
    # permanent crown mute when bacArm (even after tip clears stickyGate)
    crown = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
    if 'symbol_is("BAC") && (bacArm.is(1)' not in t:
        t = t.replace(
            crown,
            crown + ' && (!(symbol_is("BAC") && (bacArm.is(1) || bar_index < 2)))',
        )
    # rewrite BAC tip / soft
    old_tip = """    // BAC red sticky tip
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.1: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""
    new_tip = f"""    // BAC sticky tip (crown sealed via bacArm mute)
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {tip}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < {soft} * equity: {{
      stickyGate.clear()
      flat()
    }}
"""
    if old_tip not in t:
        raise SystemExit("BAC tip block missing")
    t = t.replace(old_tip, new_tip)
    return t


def main() -> int:
    for tip, soft in [(0.10, -0.12), (0.102, -0.12), (0.105, -0.12), (0.11, -0.15), (0.12, -0.15)]:
        t = bac_mild_sticky_base(BASE, tip, soft)
        write(
            f"_p_v7h4_bac_seal_tip{int(tip*1000)}_s{int(abs(soft)*100)}.ms",
            t,
            f"BAC mild sticky tip>{tip:.1%} soft{soft:.0%} + crown seal",
        )

    # XOM: quiet mildred + crown mute after quiet ends? Try shorter quiet bail
    t = BASE
    old = "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
    t = t.replace(
        old,
        old + "      when fo > -0.005 && fo < 0.0: quietArm.set(1)\n",
    )
    # shorten bail for XOM only - inject before general quiet bail
    inj = """    when quietOn && symbol_is("XOM") && bars_in_trade >= 5: bail()
"""
    t = t.replace("    when quietOn && bars_in_trade >= 8: bail()\n", inj + "    when quietOn && bars_in_trade >= 8: bail()\n")
    write("_p_v7h4_xom_quiet_bail5.ms", t, "XOM mild quiet bail@5")

    # XOM mute + forced single short at bar 5 when mild
    t = BASE
    if "xomMild = new PathLatch()" not in t:
        t = t.replace("  tslaMild = new PathLatch()\n", "  tslaMild = new PathLatch()\n  xomMild = new PathLatch()\n")
    t = t.replace(
        "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n",
        "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n      when fo > -0.005 && fo < 0.0: xomMild.set(1)\n",
    )
    crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
    t = t.replace(crown, crown + ' && (!(symbol_is("XOM") && xomMild.is(1)))')
    seed = """    when symbol_is("XOM") && xomMild.is(1) && bar_index == 5 && position() == 0: {
      tickFill()
      path.set(9)
      short()
    }
    when symbol_is("XOM") && xomMild.is(1) && path.is(9) && (bars_in_trade >= 25 || bar_index >= 55): {
      path.clear()
      flat()
    }
"""
    t = t.replace("    when quietOn && r5 > 70: {", seed + "    when quietOn && r5 > 70: {")
    write("_p_v7h4_xom_seedshort.ms", t, "XOM mild mute + bar5 short hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
