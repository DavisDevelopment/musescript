template donchHigh(len: Window) -> Bool { high >= highest(high, len) }
template donchLow(len: Window) -> Bool { low <= lowest(low, len) }
strategy Dual {
  onBar {
    when close > ema(close, 8) && donchHigh(21): long()
    when close < ema(close, 8) && donchLow(21): short()
    when rsi(close, 13) > 75: flat()
    when rsi(close, 13) < 25: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
