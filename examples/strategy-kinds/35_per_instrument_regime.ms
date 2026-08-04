strategy PerInstrumentRegime {
  // ONE program, different logic per instrument — reads the tape's asset/symbol columns.
  fast = ema(close, 8)
  slow = ema(close, 34)
  m = macd(close, 8, 21, 5)
  onBar {
    // crypto is choppy: demand a genuine breakout + positive momentum
    when asset_is("crypto") && high >= highest(high, 13) && m.hist > 0: long()
    // FX trends cleaner: a plain EMA stack is enough
    when asset_in("forex", "fx") && fast > slow: long()
    when close < slow: flat()
  }
}
