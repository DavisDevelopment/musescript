template donchianHigh(len: Window) -> Bool {

  high >= highest(high, len)

}



template donchianLow(len: Window) -> Bool {

  low <= lowest(low, len)

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



template dualRsiCascade(fastEma: Window) -> Bool {

  donchianLow(13) || rsiOverbought(13, 75) || rsiOverbought(8, 78) || rsiMomentumFail(13, 35) || rsiMomentumFail(8, 32) || belowEma(fastEma)

}



strategy S02_DualRsi75CascadeR6 {

  e8 = ema(close, 8)

  fast = ema(close, 13)



  onBar {

    when close > e8 && donchianHigh(21): long()

    when dualRsiCascade(13): flat()

  }

  onPosition {

    when unrealized_pnl < -0.05 * equity: flat()

    when bars_in_trade >= 13: flat()

    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()

    when bars_in_trade >= 5 && close < fast: flat()

  }

}

