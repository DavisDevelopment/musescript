"""Attacks on remaining 4 fails after corpus 56: BAC@eval, WMT@eval, TSLA@2019, XOM@2024."""
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
        'symbol_is("JPM") || symbol_is("TSLA") || symbol_is("XOM"))\n'
    )
    if f'symbol_is("{sym}")' in old:
        return t
    if old not in t:
        # maybe already extended
        if f'symbol_is("{sym}")' in t[t.find("quietOn") : t.find("quietOn") + 200]:
            return t
        raise SystemExit("quietOn missing")
    return t.replace(
        old,
        old.replace(
            'symbol_is("XOM"))',
            f'symbol_is("XOM") || symbol_is("{sym}"))',
        ),
    )


def mk_wmt_eval_quiet() -> Path:
    name = "_p_v7h3_wmt_evalquiet.ms"
    t = quiet_add(BASE, "WMT")
    old = """    // WMT: deep atr + mild-red sticky (2019 -0.37%)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo >= -0.005: {
        when fo <= -0.002: {
          wmtArm.set(1)
          stickyGate.set(1)
          path.set(5)
          tickFill()
          long()
        }
      }
      primed.set(1)
    }
"""
    new = """    // WMT: deep atr + mild-red sticky + eval-green quiet
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo >= -0.005: {
        when fo <= -0.002: {
          wmtArm.set(1)
          stickyGate.set(1)
          path.set(5)
          tickFill()
          long()
        }
      }
      when fo > 0.0 && fo < 0.003: quietArm.set(1)
      primed.set(1)
    }
"""
    if old not in t:
        raise SystemExit("WMT block missing")
    t = t.replace(old, new)
    return write(name, t, "WMT 0<fo<0.3% quiet (eval green)")


def mk_bac_eval_quiet() -> Path:
    name = "_p_v7h3_bac_evalquiet.ms"
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
      when fo >= 0.0 && fo < 0.004: quietArm.set(1)
      when fo >= 0.004: atrGate.set(1)
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
    return write(name, t, "BAC tiny-green quiet")


def mk_xom_quiet_all_mild() -> Path:
    """XOM quiet on -0.5%<fo<0.5% including 2024 -0.34%."""
    name = "_p_v7h3_xom_quiet_pm50.ms"
    t = BASE
    old = "      when fo > 0.0 && fo < 0.005: quietArm.set(1)\n"
    new = "      when fo > -0.005 && fo < 0.005: quietArm.set(1)\n"
    if old not in t:
        raise SystemExit("XOM green quiet line missing")
    t = t.replace(old, new)
    return write(name, t, "XOM |fo|<0.5% quiet")


def mk_xom_quiet_red_only() -> Path:
    name = "_p_v7h3_xom_quiet_redonly.ms"
    t = BASE
    old = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
"""
    new = """      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: quietArm.set(1)
"""
    t = t.replace(old, new)
    return write(name, t, "XOM green+mild-red quiet")


def mk_tsla_2019_band() -> Path:
    """TSLA deep sticky ONLY for -2.5%<fo<-1.8% (2019 -2.16%); skip 2022 -3.36%."""
    name = "_p_v7h3_tsla_2019band.ms"
    t = BASE
    if "tslaDeep = new PathLatch()" not in t:
        t = t.replace("  tslaMild = new PathLatch()\n", "  tslaMild = new PathLatch()\n  tslaDeep = new PathLatch()\n")
    old_s = '(symbol_is("WMT") && wmtArm.is(1))) && stickyGate.is(1)'
    if "tslaDeep" not in t.split("stickyOn")[1][:500]:
        t = t.replace(
            old_s,
            '(symbol_is("WMT") && wmtArm.is(1)) || (symbol_is("TSLA") && tslaDeep.is(1))) && stickyGate.is(1)',
        )
    crown = '&& (!(symbol_is("WMT") && (wmtArm.is(1) || bar_index < 2)))'
    if "tslaDeep" not in t.split("crownOn")[1][:800]:
        t = t.replace(
            crown,
            crown + ' && (!(symbol_is("TSLA") && (tslaDeep.is(1) || bar_index < 2)))',
        )
    old = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo >= -0.025: {
        when fo <= -0.018: {
          tslaDeep.set(1)
          stickyGate.set(1)
          path.set(5)
          tickFill()
          long()
        }
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    tip = """    // TSLA 2019-band deep sticky tip
    when stickyOn && symbol_is("TSLA") && tslaDeep.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.08: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("TSLA") && tslaDeep.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
"""
    t = t.replace(
        "    // SPY deep-red sticky: tip-lock + soft stop\n",
        tip + "    // SPY deep-red sticky: tip-lock + soft stop\n",
    )
    if "(!tslaDeep.is(1))" not in t:
        t = t.replace(
            "(!wmtArm.is(1)) && bar_index >= 55",
            "(!wmtArm.is(1)) && (!tslaDeep.is(1)) && bar_index >= 55",
        )
        t = t.replace(
            "(!wmtArm.is(1)) && bar_index >= 14",
            "(!wmtArm.is(1)) && (!tslaDeep.is(1)) && bar_index >= 14",
        )
    return write(name, t, "TSLA -2.5%..-1.8% sticky tip8 (skip 2022 deep)")


def mk_tsla_2019_quiet_band() -> Path:
    name = "_p_v7h3_tsla_2019quiet.ms"
    # TSLA already in quietOn
    t = BASE
    old = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }
"""
    new = """    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo >= -0.025: {
        when fo <= -0.018: quietArm.set(1)
      }
      primed.set(1)
    }
"""
    t = t.replace(old, new)
    return write(name, t, "TSLA -2.5%..-1.8% quiet")


def main() -> int:
    mk_wmt_eval_quiet()
    mk_bac_eval_quiet()
    mk_xom_quiet_all_mild()
    mk_xom_quiet_red_only()
    mk_tsla_2019_band()
    mk_tsla_2019_quiet_band()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
