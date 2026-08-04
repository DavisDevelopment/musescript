strategy CandleReversal {
  // Scale-free candle vocabulary: a bullish 2-bar reversal (a real down candle, then a strong
  // up candle) taken only above the trend filter; exit on an upper-wick exhaustion candle.
  onBar {
    when candle_dir(1) < 0 && candle_body_abs(1) > 0.4
         && candle_dir(0) > 0 && candle_body_abs(0) > 0.5
         && close > sma(close, 50): long()
    when candle_upper_wick(0) > 0.5 && candle_dir(0) > 0: flat()
    when close < sma(close, 50): flat()
  }
}
