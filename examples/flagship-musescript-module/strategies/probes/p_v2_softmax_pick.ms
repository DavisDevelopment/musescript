// Softmax regime pick between crown-likeness / ATR thrust / calm-cash.
// Uses ml_softmax over [donchBreakScore, atrThrustScore, calmScore].

class ProbeSoftmaxPick extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen) + 0.000000001
  // Scores: breakout proximity, ATR thrust intensity, calm (prefer cash)
  breakScore = (high - highest(high, donchIn)[1]) / vol
  atrScore = thrust / vol
  calmScore = -stat_stddev(window(close, 21)) / vol
  probs = ml_softmax([breakScore, atrScore, calmScore])

  function onBar() {
    when probs[0] >= probs[1] && probs[0] >= probs[2] && close > e8 && donchHigh(donchIn): long()
    when probs[1] > probs[0] && probs[1] > probs[2] && thrust > vol && rising(close, 2): long()
    when probs[2] > probs[0] && probs[2] > probs[1]: flat()
    when softCrownExit(midEma): flat()
    when thrust < 0: flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))
  }
}
