strategy VoteTest {
  fast = ema(close, 8)
  slow = ema(close, 21)
  m = macd(close, 8, 21, 5)
  onBar {
    when count_true(fast > slow, m.hist > 0, close > sma(close, 13)) >= 2: long()
    when count_true(fast > slow, m.hist > 0, close > sma(close, 13)) < 2: flat()
  }
}
