// Internal universe scanner + multi-stock portfolio (core MuseScript surface).
// Each onBar: score every live symbol by momentum, keep the top-N, equal-weight
// rebalance the shared portfolio book. Wire a PanelFeed to run over 996 names.

strategy MomUniverseScan {
  param topN = 5
  param look = 21

  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym): dict_set(scores, sym, mom_of(sym, look))
    }
    picks = scan_top(scores, topN)
    rebalance_equal(picks)
  }
}
