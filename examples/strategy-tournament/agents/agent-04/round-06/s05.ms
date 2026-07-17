template donchianHigh(len: Window) -> Bool {

  high >= highest(high, len)

}



template donchianLow(len: Window) -> Bool {

  low <= lowest(low, len)

}



template macdBear(fast: Window, slow: Window, sig: Window) -> Bool {

  macd(close, fast, slow, sig).hist < 0

}



template rsiOverbought(len: Window, hi: Scalar) -> Bool {

  rsi(close, len) > hi

}



template rsiMomentumFail(len: Window, lo: Scalar) -> Bool {

  rsi(close, len) < lo

}



template belowEma(len: Window) -> Bool {

  close < ema(close, len)

}



template rsiCrownCascade(fastEma: Window) -> Bool {

  donchianLow(13) || rsiOverbought(13, 75) || rsiOverbought(8, 78) || rsiMomentumFail(13, 35) || rsiMomentumFail(8, 32) || macdBear(13, 34, 8) || belowEma(fastEma)

}



strategy S05_RsiCrownFlagshipR6 {

  r13 = rsi(close, 13)

  m = macd(close, 13, 34, 8)

  e8 = ema(close, 8)

  fast = ema(close, 13)

  anchor = ema(close, 34)



  onBar {

    when close > e8 && donchianHigh(21): long()

    when rsiCrownCascade(13): flat()

  }

  onPosition {

    when unrealized_pnl < -0.05 * equity: flat()

    when bars_in_trade >= 13: flat()

    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()

    when bars_in_trade >= 5 && close < fast: flat()

    when bars_in_trade >= 8 && close < anchor && m.hist < 0: flat()

    when bars_in_trade >= 5 && falling(r13, 3): flat()

  }

}

