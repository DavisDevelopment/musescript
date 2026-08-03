strategy Tagged {
  onBar {
    when close > sma(close, 5): long()
    when close < sma(close, 5): flat("ma_cross")
  }
  onPosition {
    when return_since_entry() < -0.03: flat("stop_loss")
    when bars_in_trade() >= 21: flat("time_stop")
  }
}
