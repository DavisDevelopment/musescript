strategy NoTrail {
  onBar {
    when close > sma(close, 8) && close > ema(close, 21): long()
    when close < ema(close, 21): flat()
  }
}
