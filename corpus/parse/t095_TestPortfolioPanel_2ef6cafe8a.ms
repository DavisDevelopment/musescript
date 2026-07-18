
strategy MomScan {
  param topN = 3
  param look = 5
  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    picks = scan_top(scores, topN)
    rebalance_equal(picks)
  }
}
