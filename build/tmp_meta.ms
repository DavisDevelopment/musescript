template donchHigh(len: Window) -> Bool { high >= highest(high, len) }
template crownExit(fastEma: Window) -> Bool {
  low <= lowest(low, 13) || rsi(close, 13) > 75 || close < ema(close, fastEma)
}
indicator function regimeScore(_look) {
  xs = window(close, 21)
  rets = sci_diff(xs)
  bull = avg(rets)
  calm = -stat_stddev(xs)
  thrust = mom(close, 8)
  probs = ml_softmax([bull, calm, thrust])
  return probs[0]
}
class FlagshipRisk extends muse.Strat {
  param stopPct: Scalar = 0.05 { min: 0.03, max: 0.08, step: 0.025, tune: grid }
  param timeBars: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  function onPosition() {
    when unrealized_pnl < -stopPct * equity: flat()
    when bars_in_trade >= timeBars: flat()
  }
}
class FlagshipV0 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  r = rsi(close, 13)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  reg = regimeScore(21)
  function onBar() {
    if (crownExit(midEma) || reg < 0.22) {
      flat()
    } else if (close > eFast && donchHigh(donchIn)) {
      long()
    } else {
      when falling(r, 3, 5): flat()
    }
  }
}
pipeline Discover {
  walkforward(2, 3)
  promote((r) => r.sharpe > -999.0)
  tune(donchIn, midEma, stopPct, timeBars)
  optimize(sharpe)
}
