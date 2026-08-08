// Ensemble v3 — v2's broadened chop entries (bounceSig/zeroSig + deepGreen), but this time WITH
// the fill-count throttle v6l actually gates them behind, ported generic instead of
// symbol-specific. v2's diagnosis (results/BROAD8MO_REPORT.md): more entries without the
// mechanism that keeps them from overtrading looks like it just added whipsaw noise (3/54 vs
// v1's 13/54). v6l's `bounceSig`/`zeroSig` are only reachable via `admitFlat = freeRoom ||
// funnelRoom` — a budget: the first 5 fills are unrestricted, fills 6-8 require the STRONGEST
// signal only (the donchian breakout), and after 8 the sleeve seals (no new entries at all,
// existing positions still manage normally). v6l only applies this budget to "loud" symbols
// (SPY/QQQ, via symbol_is) — here it applies universally, so it's a real generalization, not a
// symbol-specific carve-out.
//
// Trend sleeve unchanged from v1/v2 (immediate entry on regime flip, wide trailing stop only).

class FlagshipEnsembleV3 extends muse.Strat {
  param donchIn: Window = 21
  param regimeFloor: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param trendRocLen: Window = 34
  param trendRocMin: Scalar = 0.07
  param trendEmaLen: Window = 34

  nFill = new PathLatch()

  reg = regimeScore(21)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  eTrend = ema(close, trendEmaLen)
  rocTrend = roc(close, trendRocLen)
  atr14 = atr(close, 14)
  gate = sma(close, 34)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  r5 = rsi(close, 5)

  trendRegime = close > eTrend && rocTrend > trendRocMin

  chopDonch = reg >= regimeFloor && close > e8 && donchHigh(donchIn)
  bounceSig = reg < bearCut && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate

  // Fill budget: unrestricted for the first 5 chop-sleeve entries; entries 6-8 need the
  // strongest signal (donchian breakout) only; sealed after 8 -- no new chop entries at all.
  freeRoom = nFill.get() < 5
  funnelRoom = nFill.get() >= 5 && nFill.get() < 8 && chopDonch
  admitFlat = freeRoom || funnelRoom
  chopEntry = admitFlat && (chopDonch || bounceSig || zeroSig)

  chopExit = softCrownExit(e13)
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1)
  }

  function onBar() {
    // Trend sleeve — unchanged from v1/v2.
    when trendRegime && position() == 0: long()
    when trendRegime && position() != 0: long()
    when trendRegime && position() != 0 && (close < eTrend || trail(3.0 * atr14)): flat()

    // Chop sleeve — broadened entries, now budget-gated like v6l's original.
    when (!trendRegime) && chopEntry: {
      when position() == 0: tickFill()
      long()
    }
    when (!trendRegime) && position() != 0 && deepGreen && donchLow(34): flat()
    when (!trendRegime) && position() != 0 && deepGreen && bars_in_trade >= 40 && r5 < 45: flat()
    when (!trendRegime) && position() != 0 && (!deepGreen) && chopExit: flat()
  }

  function hardStopped() {
    return unrealized_pnl < -0.06 * equity
  }

  function timedOut() {
    return (!trendRegime) && (!deepGreen) && bars_in_trade >= 13
  }

  function profitLocked() {
    return (!trendRegime) && (!deepGreen) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): flat()
  }
}
