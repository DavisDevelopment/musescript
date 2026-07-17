strategy MacdEma {
  onBar { m = macd(close, 8, 21, 5); t = ema(close, 21)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || close < t: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}