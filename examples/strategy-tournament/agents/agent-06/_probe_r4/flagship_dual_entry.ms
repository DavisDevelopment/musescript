strategy FlagshipDual {
  onBar { m = macd(close, 13, 34, 8); e8 = ema(close, 8); e34 = ema(close, 34)
    when high >= highest(high, 21): long()
    when e8 > e34 && high >= highest(high, 13): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}