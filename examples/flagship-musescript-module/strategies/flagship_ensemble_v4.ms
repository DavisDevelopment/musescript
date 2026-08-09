// Ensemble v4 — real diagnostic finding, not another blind broadening attempt (see v2/v3, both
// rejected). Checked directly against the broad8mo tapes (no backtest needed, just the regime
// math): trendRegime fires plenty on real strong-uptrend names -- INTC (+148.7% over the window)
// is in-regime 59% of bars, AMD (+120.2%) 55%. The gate isn't the problem.
//
// What IS the problem: trendRegime FLICKERS. INTC's on-segments are [15, 2, 1, 1, 44, 14, 1] bars
// -- several 1-2 bar noise blips alongside the one real 44-bar trend. v1/v2/v3 all re-evaluate
// "which sleeve manages this position" from LIVE trendRegime every single bar. So a position
// entered on a 1-bar flicker, the instant the flag blips back off, silently falls through to the
// CHOP sleeve's tight RSI(80)-overbought / MACD-bear / EMA-break exit rules -- the exact
// short-swing exit logic the trend sleeve exists to avoid. That's a real bug, not a parameter
// choice: it defeats the trend sleeve's whole purpose on every regime flicker, which is most of
// the segments on the most explosive movers.
//
// Fix: latch which sleeve a position was entered under (same PathLatch pattern v6l itself uses
// for entry-path tracking), and manage the position with THAT sleeve's exit rules for the whole
// trade -- never re-decided mid-trade by a noisy one-bar regime flag.
//
// ==========================================================================================
// ⚠ CORRECTION (2026-08-07, comment-only -- behaviour unchanged). THE ABOVE UNDERSTATES WHAT
// THIS FILE CHANGES. v4 is NOT "v1 plus the latch". It also silently dropped v1's
// rising(close, 3) trend-entry confirmation -- i.e. it folded in v2's ALREADY-REJECTED "enter
// immediately on regime flip" change:
//
//   v1:  when trendRegime && position() == 0 && close > eTrend && rising(close, 3): long()
//   v4:  when position() == 0 && trendRegime: { sleeve.set(1); long() }
//
// Consequences, measured across all 54 broad8mo tapes (harness/diag_sleeve_occupancy.py):
//   - the trend sleeve enters ~2x as often (down_choppy 2.5 -> 4.8 entries/symbol) and its
//     bar-occupancy rises x1.59 in down_choppy, x1.40 mild, x1.26 strong_up;
//   - an open trend position locks the chop sleeve out in BOTH versions, so this alone explains
//     the down_choppy collapse (+0.213 -> -0.620) that was originally blamed on the latch. The
//     chop sleeve's own logic is byte-identical v1 -> v4.
//
// Therefore: this file's result does NOT validate the latch, and does NOT validate the flicker
// fix. Two variables moved at once. The strong_up improvement (-0.910 -> -0.704) is
// unattributable. THE LATCH REMAINS UNTESTED -- the controlled experiment is this file with
// rising(close, 3) restored to the trend entry. Kept unmodified as a data point about what not
// to conclude. Full writeup: results/BROAD8MO_REPORT.md, "Diagnosis session (2026-08-07)".
// ==========================================================================================

class FlagshipEnsembleV4 extends muse.Strat {
  param donchIn: Window = 21
  param regimeFloor: Scalar = 0.28
  param trendRocLen: Window = 34
  // ⚠ PERCENTAGE POINTS, not a fraction -- this is 0.07%, not 7%. See flagship_ensemble_v1.ms.
  param trendRocMin: Scalar = 0.07
  param trendEmaLen: Window = 34

  sleeve = new PathLatch() // 0 = flat, 1 = trend sleeve, 2 = chop sleeve

  reg = regimeScore(21)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  eTrend = ema(close, trendEmaLen)
  rocTrend = roc(close, trendRocLen)
  atr14 = atr(close, 14)

  trendRegime = close > eTrend && rocTrend > trendRocMin
  chopEntry = reg >= regimeFloor && close > e8 && donchHigh(donchIn)
  chopExit = softCrownExit(e13)

  function onBar() {
    when position() == 0 && trendRegime: {
      sleeve.set(1)
      long()
    }
    when position() == 0 && (!trendRegime) && chopEntry: {
      sleeve.set(2)
      long()
    }
    // Latched management -- decided by which sleeve the position was entered under, not by
    // whatever trendRegime happens to read on this particular bar.
    when position() != 0 && sleeve.is(1): {
      when close < eTrend || trail(3.0 * atr14): {
        sleeve.clear()
        flat()
      }
      when position() != 0: long()
    }
    when position() != 0 && sleeve.is(2) && chopExit: {
      sleeve.clear()
      flat()
    }
    when position() != 0 && sleeve.is(2): long()
  }

  function hardStopped() {
    return unrealized_pnl < -0.06 * equity
  }

  // Time/profit-lock exits apply only to the chop sleeve, same rationale as v1 -- this is
  // precisely the mechanism that cuts trend winners short, so the trend sleeve is exempt.
  function timedOut() {
    return sleeve.is(2) && bars_in_trade >= 13
  }

  function profitLocked() {
    return sleeve.is(2) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): {
      sleeve.clear()
      flat()
    }
  }
}
