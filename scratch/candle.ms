strategy CandleTest {
  onBar {
    when candle_dir(0) > 0 && candle_body_abs(0) > 0.5 && bars_since(candle_dir(0) < 0) <= 3: long()
    when candle_dir(0) < 0 || candle_upper_wick(0) > 0.5: flat()
  }
}
