// Ensemble v2 — principled follow-up to ensemble_v1, not a re-tune against the same held-out
// numbers. Two changes, both grounded in re-reading v6l for GENERIC (non-symbol_is) signal
// families v1 left out, not in nudging thresholds until a score moved:
//
// 1. Trend sleeve entry simplified: v1 required trendRegime AND a further 3-bar rising()
//    confirmation before entering, which likely missed the early/fast part of a move — the
//    regime gate itself (roc(34) > 7%) is already real confirmation. v2 enters as soon as the
//    regime flips on while flat.
// 2. Chop sleeve broadened + a genuine "let a big winner run" carve-out ported from v6l:
//    v1's chop entry was ONLY the donchian breakout; v6l also has `bounceSig` (MACD-fast
//    turning up in a weak-regime dip) and `zeroSig` (MACD crossing zero above its gate) as
//    independent entries, and a `deepGreen` exemption (a position up >3.5% equity, held >=18
//    bars, with 13-bar momentum still positive skips the normal soft-crown exit and only bails
//    on a real structural break). None of this is symbol-specific — same zero symbol_is() calls
//    as v1.
//
// Held out ONCE at the end against the frozen baseline (ensemble_v1) — not iterated against the
// held-out score repeatedly, which would just be the same overfitting trap this whole thread
// exists to catch, one level up.

class FlagshipEnsembleV2 extends muse.Strat {
  param donchIn: Window = 21
  param regimeFloor: Scalar = 0.28
  param bearCut: Scalar = 0.22
  param trendRocLen: Window = 34
  param trendRocMin: Scalar = 0.07
  param trendEmaLen: Window = 34

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
  chopEntry = chopDonch || bounceSig || zeroSig
  chopExit = softCrownExit(e13)
  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0

  function onBar() {
    // Trend sleeve — enter immediately on regime flip, no extra confirmation gate.
    when trendRegime && position() == 0: long()
    when trendRegime && position() != 0: long()
    when trendRegime && position() != 0 && (close < eTrend || trail(3.0 * atr14)): flat()

    // Chop sleeve — broadened entry family (donchian breakout OR bounce OR MACD-zero-cross).
    when (!trendRegime) && chopEntry: {
      when position() == 0: long()
      when position() != 0: long()
    }
    // Deep-green carve-out: a real winner in the chop sleeve doesn't get cut by the normal
    // short-swing exit — only a real structural break (34-bar low) or a stalled long hold ends it.
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
