strategy ConfirmationVote {
  // N-of-M confirmation: enter only when >=2 independent signals agree (count_true),
  // exit when ALL bull conditions fail OR ANY hard stop trips (all_of / any_of).
  fast = ema(close, 8)
  slow = ema(close, 21)
  m = macd(close, 8, 21, 5)
  onBar {
    when count_true(fast > slow, m.hist > 0, close > sma(close, 34)) >= 2: long()
    when all_of(fast < slow, m.hist < 0) || any_of(close < sma(close, 55), m.hist < -0.002): flat()
  }
}
