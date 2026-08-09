// Ensemble v5 — ABLATION CELL: latch + rising(close,3).
//
// This file exists to answer one question and nothing else. ensemble_v4 is the only variant in
// this entire thread with a real, replicated, economically non-trivial effect (heldout_v2:
// +0.294 paired vs v1, +0.229 at ZERO cost, so 78% of it is signal rather than turnover). But
// v4 changed TWO things relative to v1 while its header claimed one:
//
//   v1:  trend entry = trendRegime && flat && close > eTrend && rising(close, 3)   [no latch]
//   v4:  trend entry = trendRegime && flat                                          [+ latch]
//                                    ^-- rising(close, 3) silently dropped
//
// So "the latch works" was never tested. v5 is v4 with rising(close, 3) restored, changing
// NOTHING else, which makes the four files a clean 2x2 factorial:
//
//                        no latch          latch
//   rising(close,3)      ensemble_v1       ensemble_v5   <- this file
//   no rising            ensemble_v6       ensemble_v4
//
//   v5 vs v1  isolates THE LATCH   (both have rising)
//   v5 vs v4  isolates THE ENTRY   (both have the latch)
//   the interaction says whether the latch only pays off with the looser entry
//
// Judge on heldout_v2 (9 regime folds x 300 symbols), never on broad8mo — broad8mo has ~7
// effective independent bets and its verdicts on this lineage were wrong in sign.
//
// ⚠ trendRocMin is in PERCENTAGE POINTS: 0.07 means 0.07%, not 7%. Inherited unchanged from v1/v4
// on purpose — this is an ablation, not a redesign. See flagship_ensemble_v1.ms for the details.

class FlagshipEnsembleV5 extends muse.Strat {
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
    // THE ONLY DIFFERENCE FROM v4: rising(close, 3) restored on the trend entry.
    when position() == 0 && trendRegime && rising(close, 3): {
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
