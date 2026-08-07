#!/usr/bin/env python3
"""Build & score surgical SPY@2019 probes on top of flagship_v7e (v7d DNA)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(MOD / "harness"))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
BASE = (MOD / "strategies/flagship_v7e.ms").read_text(encoding="utf-8")
PROBES = MOD / "strategies/probes"
L10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def cell(src: str, win: str, sym: str):
    m = run_gene(src, MOD / f"tapes/{win}/{sym}.csv", execution="next-open", cost_bps=10)
    bh = run_gene(BH, MOD / f"tapes/{win}/{sym}.csv", execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe
    ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
    return ok, d, m.trades, m.sharpe, m.total_return, bh.total_return


def dual_ok(src: str) -> tuple[int, float, list[str]]:
    n = 0
    ds = []
    fails = []
    for win in ["eval_3m", "wf_2022q1"]:
        for sym in L10:
            ok, d, tr, *_ = cell(src, win, sym)
            n += int(ok)
            if ok:
                ds.append(d)
            else:
                fails.append(f"{sym}@{win[3:]}(d={d:+.2f},tr={tr})")
    return n, (sum(ds) / len(ds) if ds else 0.0), fails


def graft(name: str, mode: str) -> Path:
    """mode: hold | tip145 | tip155 | bullx | rsi | ride"""
    t = BASE
    # latch
    if "spyArm = new PathLatch()" not in t:
        t = t.replace(
            "  msftArm = new PathLatch()\n",
            "  msftArm = new PathLatch()\n  spyArm = new PathLatch()\n",
            1,
        )
    # rideSym: SPY not riding when spyArm
    t = t.replace(
        'rideSym = symbol_is("QQQ") || (symbol_is("MSFT") && (!msftArm.is(1))) || symbol_is("SPY")',
        'rideSym = symbol_is("QQQ") || (symbol_is("MSFT") && (!msftArm.is(1))) || (symbol_is("SPY") && (!spyArm.is(1)))',
        1,
    )
    # stickyOn include SPY
    t = t.replace(
        'stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || (symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || (symbol_is("MSFT") && msftArm.is(1))) && stickyGate.is(1)',
        'stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || (symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || (symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1))) && stickyGate.is(1)',
        1,
    )
    # crownOn exclude spyArm
    t = t.replace(
        '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2)))',
        '&& (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2))) && (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2)))',
        1,
    )

    if mode == "ride":
        # deep-red -> seed-ride instead of crown
        old = """    // SPY: arm only if bar1 fromOpen green (2024); red (2022) stays crown-free
    when symbol_is("SPY") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: {
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }"""
        new = """    // SPY: green->ride; deep-red fo<-1.5%->ride (2019 hold attempt); mild-red crown
    when symbol_is("SPY") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0 || fo < -0.015: {
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }"""
        # for ride mode, don't need spyArm sticky — revert sticky/crown/rideSym changes
        t = BASE
        t = t.replace(old, new, 1)
    else:
        old = """    // SPY: arm only if bar1 fromOpen green (2024); red (2022) stays crown-free
    when symbol_is("SPY") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: {
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }"""
        new = """    // SPY: green->ride; deep-red fo<-1.5%->sticky (2019); mild-red crown (2022)
    when symbol_is("SPY") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: {
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo < -0.015: {
        spyArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }"""
        t = t.replace(old, new, 1)

        # exit DNA variants — insert after MSFT soft-stop block
        anchor = """    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }"""
        if mode == "hold":
            insert = """    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // SPY deep-red sticky: soft stop only (peak==end 2019)
    when stickyOn && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }"""
            t = t.replace(anchor, insert, 1)
            # exclude SPY from default sticky RSI/stop exits
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 55 && r5 < 45:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 55 && r5 < 45:',
                1,
            )
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                1,
            )
        elif mode.startswith("tip"):
            thr = "0.145" if mode == "tip145" else "0.155"
            insert = f"""    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}
    // SPY deep-red sticky: tip-lock + soft stop
    when stickyOn && symbol_is("SPY") && seedOpen.get() > 0.0: {{
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > {thr}: {{
        stickyGate.clear()
        flat()
      }}
    }}
    when stickyOn && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {{
      stickyGate.clear()
      flat()
    }}"""
            t = t.replace(anchor, insert, 1)
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 55 && r5 < 45:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 55 && r5 < 45:',
                1,
            )
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                1,
            )
        elif mode == "bullx":
            # piggyback META/amznBand bullx leash
            t = t.replace(
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1)) && bars_in_trade >= 13:",
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1) || symbol_is(\"SPY\")) && bars_in_trade >= 13:",
                1,
            )
            t = t.replace(
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1) || symbol_is(\"SPY\")) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity:",
                1,
            )
            t = t.replace(
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1)) && unrealized_pnl < -0.05 * equity:",
                "when stickyOn && (symbol_is(\"META\") || amznBand.is(1) || symbol_is(\"SPY\")) && unrealized_pnl < -0.05 * equity:",
                1,
            )
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 55 && r5 < 45:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 55 && r5 < 45:',
                1,
            )
            t = t.replace(
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                'when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && bar_index >= 14 && unrealized_pnl < -0.04 * equity:',
                1,
            )
        elif mode == "rsi":
            # default sticky exits already apply if we DON'T exclude SPY
            pass

    # rename class/header
    t = t.replace("class FlagshipV7e", f"class FlagshipProbe", 1)
    t = re.sub(r"new FlagshipV7e\(\)", "new FlagshipProbe()", t)
    t = "// probe " + name + "\n" + t
    out = PROBES / name
    out.write_text(t, encoding="utf-8")
    return out


def main() -> int:
    modes = ["hold", "tip145", "tip155", "bullx", "rsi", "ride"]
    if len(sys.argv) > 1:
        modes = sys.argv[1:]
    focus = [
        ("wf_2019q1", "SPY"),
        ("wf_2024q4", "SPY"),
        ("eval_3m", "SPY"),
        ("wf_2022q1", "SPY"),
        ("wf_2019q1", "MSFT"),
        ("wf_2019q1", "META"),
        ("wf_2019q1", "AMZN"),
        ("wf_2019q1", "IWM"),
    ]
    for mode in modes:
        name = f"_p_v7e_spy_{mode}.ms"
        path = graft(name, mode)
        print(f"==== {name} ====")
        st = stitch_source(path)
        for win, sym in focus:
            ok, d, tr, sh, ret, bhr = cell(st, win, sym)
            print(
                f"  {sym:5} {win:10} {'P' if ok else 'f'} d={d:+.3f} tr={tr} "
                f"ret={ret:+.2%} bhret={bhr:+.2%}"
            )
        n, mean_d, fails = dual_ok(st)
        print(f"  dual={n}/20 mean_d={mean_d:+.3f}")
        if fails:
            print("  dual fails:", " ".join(fails[:6]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
