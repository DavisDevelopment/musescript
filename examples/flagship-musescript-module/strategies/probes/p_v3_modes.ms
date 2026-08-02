// Softmax mode picker — sticky / ATR / crown / MACD bounce.

class ProbeV3Modes extends FlagshipRisk {
  param donchIn: Window = 21
  param midEma: Window = 13
  param momLen: Window = 13

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  probs = modeMasses(21)
  sticky = probs[0] >= probs[1] && probs[0] >= probs[2] && probs[0] >= probs[3]
  atrMode = probs[1] > probs[0] && probs[1] >= probs[2] && probs[1] >= probs[3]
  crownMode = probs[2] > probs[0] && probs[2] > probs[1] && probs[2] >= probs[3]
  bounceMode = probs[3] > probs[0] && probs[3] > probs[1] && probs[3] > probs[2]
  seedish = position() > 0 && bars_in_trade >= bar_index - 2

  function onBar() {
    // Sticky mode: seed + hold
    when sticky && bar_index == 1: long()
    when sticky && position() == 0 && close > e8: long()
    when sticky && seedish && bar_index >= 55 && r5 < 45: flat()

    // ATR mode (AAPL DNA)
    when atrMode && thrust > vol && rising(close, 2): long()
    when atrMode && (close < e8 || r > 80): flat()

    // Crown mode (index DNA)
    when crownMode && close > e8 && donchHigh(donchIn): long()
    when crownMode && softCrownExit(midEma): flat()

    // Bounce / MACD mode (MSFT DNA)
    when bounceMode && crossover(mz.hist, 0) && close > gate: long()
    when bounceMode && rising(mf.hist, 3) && close > gate: long()
    when bounceMode && (mz.hist < 0 || bars_in_trade >= 13): flat()

    // Fallback soft exit when not sticky-seed
    when (!sticky) && (!atrMode) && softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return (!sticky) && (super.hardStopped() || (bars_in_trade >= 5 && close < e13))
  }

  function timedOut() {
    return (!sticky) && (super.timedOut() || (bars_in_trade >= 8 && close < e34 && m.hist < 0))
  }

  function profitLocked() {
    return (!sticky) && (super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3)))
  }
}
