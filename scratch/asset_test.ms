strategy AssetGateTest {
  onBar {
    when asset_is("crypto") && close > sma(close, 5): long()
    when close < sma(close, 5): flat()
  }
}
