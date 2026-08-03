strategy VoteManual {
  fast = ema(close, 8)
  slow = ema(close, 21)
  m = macd(close, 8, 21, 5)
  onBar {
    when (fast > slow && m.hist > 0) || (fast > slow && close > sma(close, 13)) || (m.hist > 0 && close > sma(close, 13)): long()
    when !((fast > slow && m.hist > 0) || (fast > slow && close > sma(close, 13)) || (m.hist > 0 && close > sma(close, 13))): flat()
  }
}
