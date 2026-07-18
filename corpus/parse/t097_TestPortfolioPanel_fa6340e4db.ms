
strategy FundGate {
  onBar {
    when sym_available("AAA") && !na(fund_of("AAA", "revenue")) && pos("AAA") == 0: buy("AAA", 1)
  }
}
