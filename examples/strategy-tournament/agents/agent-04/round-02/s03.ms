strategy RsiDipDonchianExit {
  r = rsi(close, 13)
  trend = ema(close, 34)
  onBar {
    when position() == 0 && close > trend && r < 42: long()
    when position() != 0 && (high >= highest(high, 13) || r > 68): flat()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
