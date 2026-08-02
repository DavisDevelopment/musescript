// Ceiling sleeve — EMA13 flip (MSFT strong solo; dangerous on bulls).

strategy LongShortFlipSleeve {
  e = ema(close, 13)
  onBar {
    when close > e && rising(close, 2): long()
    when close < e && falling(close, 2): short()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
