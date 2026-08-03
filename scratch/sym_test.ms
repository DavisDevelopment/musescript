strategy OnlyBtc {
  onBar {
    when symbol_is("BTCUSD") && close > sma(close, 5): long()
    when close < sma(close, 5): flat()
  }
}
