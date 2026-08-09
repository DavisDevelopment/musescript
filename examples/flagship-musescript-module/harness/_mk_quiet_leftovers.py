"""Quiet-sleeve probes for remaining leftovers on post-JPM-quiet v7h."""
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


def quiet_add_sym(t: str, sym: str) -> str:
    old = '  quietOn = quietArm.is(1) && (symbol_is("AMD") || symbol_is("GOOGL") || symbol_is("JPM"))\n'
    clause = f'symbol_is("{sym}")'
    if clause in old and clause in t.split("quietOn")[1][:200]:
        # already in quietOn
        pass
    if old not in t:
        raise SystemExit("quietOn line missing (need folded v7h)")
    if clause in t[t.find("quietOn") : t.find("quietOn") + 160]:
        return t
    t = t.replace(
        old,
        old.replace(
            'symbol_is("JPM"))',
            f'symbol_is("JPM") || {clause})',
        ),
    )
    return t


def mk_xom_mild_quiet(lo: float = -0.005, hi: float = 0.0) -> Path:
    name = f"_p_v7h_xom_mildquiet{int(abs(lo)*10000)}.ms"
    t = quiet_add_sym(BASE, "XOM")
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
    if old not in t:
        raise SystemExit("XOM block missing")
    t = t.replace(old, new)
    return write(name, t, f"XOM {lo}<fo<{hi} quiet (2024 mild)")


def mk_tsla_hot_quiet(cut: float = 0.04) -> Path:
    name = f"_p_v7h_tsla_hotquiet{int(cut*1000)}.ms"
    t = quiet_add_sym(BASE, "TSLA")
    catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && (!symbol_is("JPM")) '
        '&& (!symbol_is("XOM")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)\n'
    )
    arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > {cut}: quietArm.set(1)
      primed.set(1)
    }}
"""
    if catch not in t:
        raise SystemExit("catch missing")
    if '(!symbol_is("TSLA"))' not in t:
        catch_new = catch.replace(
            '(!symbol_is("XOM"))',
            '(!symbol_is("XOM")) && (!symbol_is("TSLA"))',
        )
        t = t.replace(catch, arm + catch_new)
    else:
        raise SystemExit("TSLA already in catch")
    return write(name, t, f"TSLA fo>{cut} quiet (eval hot)")


def mk_tsla_mild_quiet(hi: float = 0.015) -> Path:
    name = f"_p_v7h_tsla_mildquiet{int(hi*1000)}.ms"
    t = quiet_add_sym(BASE, "TSLA")
    catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && (!symbol_is("JPM")) '
        '&& (!symbol_is("XOM")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)\n'
    )
    arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.0 && fo < {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    if '(!symbol_is("TSLA"))' in t[t.find("catch") if False else 0 :]:
        pass
    if catch not in t:
        raise SystemExit("catch missing")
    catch_new = catch.replace(
        '(!symbol_is("XOM"))',
        '(!symbol_is("XOM")) && (!symbol_is("TSLA"))',
    )
    t = t.replace(catch, arm + catch_new)
    return write(name, t, f"TSLA 0<fo<{hi} quiet (2024 mild)")


def mk_bac_green_quiet(cut: float = 0.0) -> Path:
    """BAC fo >= cut → quiet instead of atr (eval +0.13%). Risk 2022 green."""
    name = f"_p_v7h_bac_greenquiet.ms"
    t = quiet_add_sym(BASE, "BAC")
    # remove BAC from atrOn
    t = t.replace(
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
    )
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
      when fo >= {cut} && fo < 0.005: quietArm.set(1)
      when fo >= 0.005: atrGate.set(1)
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
    # restore atr BAC for hot
    t = t.replace(
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
        '  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))\n',
    )
    if old not in t:
        raise SystemExit("BAC block missing")
    t = t.replace(old, new)
    return write(name, t, "BAC mild-green quiet; hot atr")


def mk_wmt_mild_quiet(lo: float = -0.008, hi: float = 0.0) -> Path:
    """WMT mild red/flat → quiet. Hits 2019 (-0.37%) and maybe 2024 (-0.69%)."""
    name = f"_p_v7h_wmt_mildquiet{int(abs(lo)*10000)}.ms"
    t = quiet_add_sym(BASE, "WMT")
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: deep atr + mild quiet
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo > {lo} && fo < {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    if old not in t:
        raise SystemExit("WMT block missing")
    t = t.replace(old, new)
    return write(name, t, f"WMT {lo}<fo<{hi} quiet")


def mk_wmt_band_quiet(lo: float = -0.005, hi: float = -0.002) -> Path:
    name = f"_p_v7h_wmt_bandquiet{int(abs(lo)*10000)}_{int(abs(hi)*10000)}.ms"
    t = quiet_add_sym(BASE, "WMT")
    old = """    // WMT: strict-red bar1 fo < -1% → atr (2022 -1.42%; 2024 -0.69% stays crown)
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      primed.set(1)
    }
"""
    new = f"""    // WMT: deep atr + band quiet
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo > {lo} && fo < {hi}: quietArm.set(1)
      primed.set(1)
    }}
"""
    t = t.replace(old, new)
    return write(name, t, f"WMT {lo}<fo<{hi} quiet (2019 band)")


def mk_tsla_deep_quiet(cut: float = -0.02) -> Path:
    """TSLA fo < cut quiet — 2019 (-2.16%) and 2022 (-3.36%). Risk regressing 2022 pass."""
    name = f"_p_v7h_tsla_deepquiet{int(abs(cut)*1000)}.ms"
    t = quiet_add_sym(BASE, "TSLA")
    catch = (
        '    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) '
        '&& (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) '
        '&& (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && (!symbol_is("JPM")) '
        '&& (!symbol_is("XOM")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)\n'
    )
    arm = f"""    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {{
      fo = (close - open) / open
      when fo < {cut}: quietArm.set(1)
      primed.set(1)
    }}
"""
    catch_new = catch.replace(
        '(!symbol_is("XOM"))',
        '(!symbol_is("XOM")) && (!symbol_is("TSLA"))',
    )
    t = t.replace(catch, arm + catch_new)
    return write(name, t, f"TSLA fo<{cut} quiet")


def main() -> int:
    mk_xom_mild_quiet(-0.005, 0.0)
    mk_xom_mild_quiet(-0.01, 0.0)
    mk_tsla_hot_quiet(0.04)
    mk_tsla_hot_quiet(0.05)
    mk_tsla_mild_quiet(0.015)
    mk_tsla_mild_quiet(0.02)
    mk_bac_green_quiet()
    mk_wmt_mild_quiet(-0.008, 0.0)
    mk_wmt_band_quiet(-0.005, -0.002)
    mk_wmt_band_quiet(-0.0045, -0.003)
    mk_tsla_deep_quiet(-0.02)
    mk_tsla_deep_quiet(-0.025)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
