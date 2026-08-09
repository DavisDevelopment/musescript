"""Post-TSLA-quiet leftovers: XOM mild tip-trade, BAC tip ATR, WMT nested band quiet."""
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
        'symbol_is("JPM") || symbol_is("TSLA"))\n'
    )
    if old not in t:
        raise SystemExit("quietOn missing")
    if f'symbol_is("{sym}")' in old:
        return t
    return t.replace(
        old,
        old.replace(
            'symbol_is("TSLA"))',
            f'symbol_is("TSLA") || symbol_is("{sym}"))',
        ),
    )


def mk_xom_green_quiet(lo: float = 0.0, hi: float = 0.01) -> Path:
    """XOM mild green → quiet. Hits eval +0.28%; skips 2022 hot +2.8% if hi<=0.02? 2.8%>hi."""
    name = f"_p_v7h_xom_greenquiet{int(hi*1000)}.ms"
    t = quiet_add(BASE, "XOM")
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
      when fo > {lo} && fo < {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    t = t.replace(old, new)
    return write(name, t, f"XOM {lo}<fo<{hi} quiet (eval green)")


def mk_xom_mild_earlyflat(lo: float = -0.005, hi: float = 0.0, until: int = 25) -> Path:
    """XOM mild → mute crown only for bar_index < until (temp mute via doneGate-style latch clear)."""
    name = f"_p_v7h_xom_tempmute{until}.ms"
    t = BASE
    # use doneGate as mute? better: seedOpen latch xomMild + crown mute with bar_index < until
    if "xomMild = new PathLatch()" not in t:
        t = t.replace("  xomArm = new PathLatch()\n", "  xomArm = new PathLatch()\n  xomMild = new PathLatch()\n")
    crown = '&& (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2)))'
    if "xomMild.is(1) && bar_index" not in t:
        t = t.replace(
            crown,
            crown + f' && (!(symbol_is("XOM") && xomMild.is(1) && bar_index < {until}))',
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
    t = t.replace(old, new)
    return write(name, t, f"XOM mild crown-mute bars<{until}")


def mk_wmt_nested_quiet() -> Path:
    name = "_p_v7h_wmt_nestedquiet.ms"
    t = quiet_add(BASE, "WMT")
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = """    // WMT: deep atr + nested mild-red quiet (2019)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo > -0.005: {
        when fo < -0.002: quietArm.set(1)
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    return write(name, t, "WMT nested -0.5%<fo<-0.2% quiet")


def mk_bac_atr_tip() -> Path:
    """No-op structural — BAC atr already; try sticky tip widen on red only tip20 for 2019 already pass.
    Instead: BAC green quiet but only fo in [0, 0.003] tighter."""
    name = "_p_v7h_bac_tinyquiet.ms"
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
      when fo >= 0.0 && fo < 0.003: quietArm.set(1)
      when fo >= 0.003: atrGate.set(1)
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
    return write(name, t, "BAC fo in [0,0.3%) quiet; else atr")


def mk_tsla_2024_sticky_tip(tip: float = 0.50) -> Path:
    """Fix prior sticky: do NOT crown-mute permanently without ensuring sticky holds;
    use rideSym-like sticky with bar_index<2 mute only."""
    name = f"_p_v7h_tsla_mildsticky_fix{int(tip*100)}.ms"
    t = BASE
    if "tslaArm = new PathLatch()" not in t:
        t = t.replace("  xomArm = new PathLatch()\n", "  xomArm = new PathLatch()\n  tslaArm = new PathLatch()\n")
    # sticky add
    old_s = '(symbol_is("JPM") && jpmArm.is(1))) && stickyGate.is(1)'
    if '(symbol_is("TSLA") && tslaArm.is(1))' not in t:
        t = t.replace(
            old_s,
            '(symbol_is("JPM") && jpmArm.is(1)) || (symbol_is("TSLA") && tslaArm.is(1))) && stickyGate.is(1)',
        )
    # mute crown on bar1 only + while sticky armed (same as XOM pattern)
    crown = '&& (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2)))'
    if 'symbol_is("TSLA") && (tslaArm.is(1)' not in t:
        t = t.replace(
            crown,
            crown + ' && (!(symbol_is("TSLA") && (tslaArm.is(1) || bar_index < 2)))',
        )
    # extend existing TSLA bar1 block
    old = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      primed.set(1)
    }
"""
    new = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {{
        tslaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }}
      primed.set(1)
    }}
"""
    t = t.replace(old, new)
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
    t = t.replace(
        "    // SPY deep-red sticky: tip-lock + soft stop\n",
        tip_block + "    // SPY deep-red sticky: tip-lock + soft stop\n",
    )
    for tok in ["(!jpmArm.is(1))"]:
        if "(!tslaArm.is(1))" not in t:
            t = t.replace(
                tok + " && bar_index >= 55",
                tok + " && (!tslaArm.is(1)) && bar_index >= 55",
            )
            t = t.replace(
                tok + " && bar_index >= 14",
                tok + " && (!tslaArm.is(1)) && bar_index >= 14",
            )
    return write(name, t, f"TSLA mild sticky tip>{tip:.0%} + XOM-style early mute")


def main() -> int:
    mk_xom_green_quiet(0.0, 0.01)
    mk_xom_green_quiet(0.0, 0.005)
    mk_xom_mild_earlyflat(-0.005, 0.0, 20)
    mk_xom_mild_earlyflat(-0.005, 0.0, 30)
    mk_wmt_nested_quiet()
    mk_bac_atr_tip()
    mk_tsla_2024_sticky_tip(0.50)
    mk_tsla_2024_sticky_tip(0.60)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
