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



template rsi75VaultExit() -> Bool {

  donchianLow(13) || rsiOverbought(13, 75) || rsiMomentumFail(13, 35)

}



strategy S01_Rsi75TakeVaultR6 {

  e8 = ema(close, 8)



  onBar {

    when close > e8 && donchianHigh(21): long()

    when rsi75VaultExit(): flat()

  }

  onPosition {

    when unrealized_pnl < -0.05 * equity: flat()

    when bars_in_trade >= 13: flat()

    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()

  }

}

