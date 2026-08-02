// Hybrid: crown breakout always; OR secondary ONLY when regime is weak (bear bounce).
// Regime is a mode switch — never an entry veto on the crown path.

class ProbeRegimeHybrid extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param regimeCut: Scalar = 0.30 { min: 0.22, max: 0.38, step: 0.04, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  reg = regimeScore(21)

  function onBar() {
    // Primary: tournament crown (bull tape workhorse)
    when close > e8 && donchHigh(donchIn): long()
    // Secondary: weak-regime participation (2022 DNA) — does not block crown
    when reg < regimeCut && (e8 > e13 || rising(m.hist, 3)) && close > gate: long()
    when crownExit(midEma): flat()
    when falling(r, 3, 5): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || falling(r, 3)
  }
}

pipeline DiscoverHybrid {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, stopPct, timeBars, regimeCut)
  optimize(sharpe)
}
