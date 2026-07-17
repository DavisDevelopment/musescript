template donchianLow(len: Window) -> Bool {
  low <= lowest(low, len)
}

template rsiOverbought(len: Window, hi: Scalar) -> Bool {
  rsi(close, len) > hi
}

template belowEma(len: Window) -> Bool {
  close < ema(close, len)
}

template rsiRecoveryExit(fastEma: Window) -> Bool {
  donchianLow(13) || rsiOverbought(13, 68) || belowEma(fastEma)
}

strategy S04_RsiRecoveryVaultR5 {
  onBar {
    r = rsi(close, 8)
    e8 = ema(close, 8)
    e34 = ema(close, 34)
    when position() == 0 && e8 > e34 && r > 35 && r[1] <= 35: long()
    when position() != 0 && rsiRecoveryExit(13): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
  }
}
