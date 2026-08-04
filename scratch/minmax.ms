strategy MinMax {
  onBar {
    when min(close, close + 1) == close && max(close, close - 1) == close: long()
    when min(close, close + 1) > close: flat()
  }
}
