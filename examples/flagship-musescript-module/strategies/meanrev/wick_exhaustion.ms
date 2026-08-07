// Mean-reversion #17 — seller-exhaustion wick: a long lower wick (rejection of
// lower prices within the bar) on a down day signals the sell pressure ran out
// intraperiod. Single-candle price-action pattern — no lookback window at all
// beyond the current bar's own OHLC shape.

strategy WickExhaustion {
  lw = candle_lower_wick(0)
  body = candle_body(0)
  onBar {
    when lw > 0.5 && body < 0: long()
    when body > 0 && rising(close, 2): flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 5: flat()
  }
}
