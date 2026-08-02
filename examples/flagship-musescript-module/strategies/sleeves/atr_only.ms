// Ceiling sleeve — ATR thrust alone (AAPL/META bakeoff winner).

strategy AtrOnlySleeve {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  e8 = ema(close, 8)
  r = rsi(close, 13)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when close < e8 || r > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 5 && falling(r, 3): flat()
  }
}
