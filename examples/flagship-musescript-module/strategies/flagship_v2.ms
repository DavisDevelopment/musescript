// Flagship v2 — multi-family entries, single soft-crown exit stack.
//
// Bakeoff lesson: ATR alone PASSes AAPL/META; union with ATR *exits* nuked AAPL.
// So: OR entries, shared softCrownExit + class risk only (no thrust<0 flat).
// ATR path only when regime is not deeply weak; MACD bounce only when it is.

class FlagshipV2 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param momLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bullCut: Scalar = 0.28 { min: 0.20, max: 0.36, step: 0.04, tune: grid }
  param bearCut: Scalar = 0.22 { min: 0.14, max: 0.28, step: 0.04, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  mf = macd(close, 8, 21, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  thrust = mom(close, momLen)
  vol = atr(close, momLen)
  reg = regimeScore(21)

  function onBar() {
    // Family A — tournament crown (indexes / semis workhorse)
    when close > e8 && donchHigh(donchIn): long()
    // Family B — ATR thrust only outside deep-bear regime (AAPL/META DNA)
    when reg >= bullCut && thrust > vol && rising(close, 2): long()
    // Family C — MACD-rise bounce only in weak regime (2022 AMZN/MSFT DNA)
    when reg < bearCut && rising(mf.hist, 3) && close > gate: long()
    // One exit stack — soft crown only (do NOT attach ATR thrust<0 flats)
    when softCrownExit(midEma): flat()
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

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, midEma, momLen, stopPct, timeBars, bullCut, bearCut)
  optimize(sharpe)
}
