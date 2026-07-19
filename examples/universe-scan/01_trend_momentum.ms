// S1 — Trend-gated cross-sectional momentum.
// Only rank names in a confirmed uptrend (above their long MA); long the top-N by
// medium-horizon momentum, equal-weight. The per-name trend filter avoids falling knives
// and doubles as an implicit regime gate: in a broad downtrend few names qualify -> mostly cash.
strategy TrendMomScan {
  param topN = 15
  param momLook = 126
  param trendLook = 200

  onBar {
    scores = dict_new()
    for (sym in symbols()) {
      when sym_available(sym) && close_of(sym) > sma_of(sym, trendLook):
        dict_set(scores, sym, mom_of(sym, momLook))
    }
    picks = scan_top(scores, topN)
    rebalance_equal(picks)
  }
}
