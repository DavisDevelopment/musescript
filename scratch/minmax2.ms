strategy MinMax2 {
  onBar {
    when min(close + 1, close) == close && max(close - 1, close) == close: long()
    when min(close + 1, close) > close: flat()
  }
}
