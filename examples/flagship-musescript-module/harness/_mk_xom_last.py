"""XOM@2024 last-cell probes: immediate short / long-hold quiet / tip short."""
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


def mk_xom_imm_short() -> Path:
    name = "_p_v7h5_xom_immshort.ms"
    t = BASE
    old = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
"""
    new = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: {
        quietArm.set(1)
        tickFill()
        path.set(9)
        short()
      }
"""
    t = t.replace(old, new)
    # longer XOM quiet hold
    t = t.replace(
        "    when quietOn && bars_in_trade >= 8: bail()\n",
        """    when quietOn && symbol_is("XOM") && bars_in_trade >= 40: bail()
    when quietOn && (!symbol_is("XOM")) && bars_in_trade >= 8: bail()
""",
    )
    return write(name, t, "XOM mild-red imm short hold40")


def mk_xom_imm_short_tip() -> Path:
    name = "_p_v7h5_xom_immshort_tip.ms"
    t = BASE
    if "xomShort = new PathLatch()" not in t:
        t = t.replace("  tslaMild = new PathLatch()\n", "  tslaMild = new PathLatch()\n  xomShort = new PathLatch()\n")
    old = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
"""
    new = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: {
        xomShort.set(1)
        seedOpen.set(open)
        tickFill()
        path.set(9)
        short()
      }
"""
    t = t.replace(old, new)
    # mute crown while xomShort
    crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
    t = t.replace(crown, crown + ' && (!(symbol_is("XOM") && xomShort.is(1)))')
    tip = """    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < -0.08: {
        xomShort.clear()
        path.clear()
        flat()
      }
      when fo > 0.03: {
        xomShort.clear()
        path.clear()
        flat()
      }
    }
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= 45: {
      xomShort.clear()
      path.clear()
      flat()
    }
"""
    t = t.replace("    when quietOn && r5 > 70: {", tip + "    when quietOn && r5 > 70: {")
    return write(name, t, "XOM mild-red short tip -8%/+3%")


def mk_xom_imm_short_sweep() -> list:
    outs = []
    for cover_down, cover_up, hold in [
        (-0.06, 0.02, 40),
        (-0.08, 0.03, 45),
        (-0.10, 0.04, 50),
        (-0.12, 0.02, 55),
        (-0.05, 0.015, 35),
    ]:
        t = BASE
        if "xomShort = new PathLatch()" not in t:
            t = t.replace(
                "  tslaMild = new PathLatch()\n",
                "  tslaMild = new PathLatch()\n  xomShort = new PathLatch()\n",
            )
        old = "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
        new = f"""      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: {{
        xomShort.set(1)
        seedOpen.set(open)
        tickFill()
        path.set(9)
        short()
      }}
"""
        t = t.replace(old, new)
        crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
        if "xomShort.is(1)" not in t.split("crownOn")[1][:900]:
            t = t.replace(crown, crown + ' && (!(symbol_is("XOM") && xomShort.is(1)))')
        tip = f"""    when symbol_is("XOM") && xomShort.is(1) && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo < {cover_down}: {{
        xomShort.clear()
        path.clear()
        flat()
      }}
      when fo > {cover_up}: {{
        xomShort.clear()
        path.clear()
        flat()
      }}
    }}
    when symbol_is("XOM") && xomShort.is(1) && bars_in_trade >= {hold}: {{
      xomShort.clear()
      path.clear()
      flat()
    }}
"""
        t = t.replace("    when quietOn && r5 > 70: {", tip + "    when quietOn && r5 > 70: {")
        outs.append(
            write(
                f"_p_v7h5_xom_sh{int(abs(cover_down)*100)}_{int(cover_up*1000)}_h{hold}.ms",
                t,
                f"XOM short cover {cover_down}/{cover_up} hold{hold}",
            )
        )
    return outs


def main() -> int:
    mk_xom_imm_short()
    mk_xom_imm_short_tip()
    mk_xom_imm_short_sweep()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
