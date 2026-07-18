
strategy MomScanJs {
  param topN = 2
  param look = 4
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    rebalance_equal(scan_top(scores, topN))
  }
}
