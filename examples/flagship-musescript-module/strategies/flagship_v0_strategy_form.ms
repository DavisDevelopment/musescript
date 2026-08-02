// Strategy-form twin — exercises module `use` + stmt SoftStop metaprogramming
// that class bodies cannot host. Same signal idea as flagship_v0; no pipeline
// class inheritance. Use when iterating the expansion-based risk kits.

strategy FlagshipV0StrategyForm {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param slowEma: Window = 34 { min: 21, max: 55, step: 13, tune: grid }
  param rsiLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bbLen: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param regimeFloor: Scalar = 0.22 { min: 0.15, max: 0.30, step: 0.05, tune: grid }
  param stopPct: Scalar = 0.05 { min: 0.03, max: 0.08, step: 0.01, tune: grid }
  param timeBars: Window = 13 { min: 8, max: 21, step: 5, tune: grid }

  r = rsi(close, rsiLen)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, slowEma)
  bb = bbands(close, bbLen, 2.0)
  reg = regimeScore(21)

  SoftStop(0.05)
  use RiskKit(stopPct = 0.05, timeBars = 13, lockBars = 8, lockPct = 0.03)

  onBar() when (crownExit(midEma) || reg < regimeFloor) {
    flat()
  }
  onBar() when (close > eFast && donchHigh(donchIn)) {
    long()
  }
  onBar() {
    when falling(r, 3, 5): flat()
  }

  onPosition {
    when bars_in_trade >= 5 && close < eMid: flat()
    when bars_in_trade >= 8 && close < eSlow && m.hist < 0: flat()
    when bars_in_trade >= 5 && falling(r, 3): flat()
    when close >= bb.upper && unrealized_pnl > 0: flat()
  }
}

pipeline DiscoverStrategyForm {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, fastEma, midEma, stopPct, timeBars, regimeFloor)
  optimize(sharpe)
}
