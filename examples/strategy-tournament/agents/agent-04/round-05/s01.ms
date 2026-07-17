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

template rsiTakeVaultExit() -> Bool {
  donchianLow(13) || rsiOverbought(13, 72) || rsiMomentumFail(13, 35)
}

strategy S01_RsiTakeVaultR5 {
  onBar {
    when donchianHigh(21): long()
    when rsiTakeVaultExit(): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
  }
}
