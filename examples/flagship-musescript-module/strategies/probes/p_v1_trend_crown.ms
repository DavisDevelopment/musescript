// Trend-gated long-only crown — H1/H3 DNA + e8>e13 participation (anti-whipsaw).

class ProbeTrendCrown extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param slowEma: Window = 34 { min: 21, max: 55, step: 13, tune: grid }
  param rsiHotLvl: Scalar = 75 { min: 70, max: 80, step: 5, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, slowEma)
  reg = regimeScore(21)

  function onBar() {
    // Entry: Donchian breakout only with short-term trend alignment (no regime gate).
    when close > eFast && eFast > eMid && donchHigh(donchIn): long()
    // Exit: classic crown cascade (exit-only filters).
    when crownExit(midEma) || rsiHot(13, rsiHotLvl): flat()
    when falling(r, 3, 5): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < eMid)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < eSlow && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || falling(r, 3)
  }
}

pipeline DiscoverTrendCrown {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, fastEma, midEma, stopPct, timeBars, rsiHotLvl)
  optimize(sharpe)
}
