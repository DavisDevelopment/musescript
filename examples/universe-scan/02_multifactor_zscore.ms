// S2 — Multi-factor cross-sectional z-score blend (inlined, no helper fn).
// Four decorrelated factors, each z-scored across the uptrend universe, then blended.
strategy MultiFactorZ {
  param topN = 15
  param trendLook = 200

  onBar {
    momD = dict_new()
    revD = dict_new()
    trdD = dict_new()
    rsiD = dict_new()
    for (sym in symbols()) {
      when sym_available(sym) && close_of(sym) > sma_of(sym, trendLook): {
        dict_set(momD, sym, mom_of(sym, 126))
        dict_set(revD, sym, 0 - mom_of(sym, 5))
        dict_set(trdD, sym, close_of(sym) / sma_of(sym, 50) - 1)
        dict_set(rsiD, sym, 50 - rsi_of(sym, 14))
      }
    }
    mMu = stat_mean(dict_values(momD))
    mSd = stat_stddev(dict_values(momD)) + 0.000001
    rMu = stat_mean(dict_values(revD))
    rSd = stat_stddev(dict_values(revD)) + 0.000001
    tMu = stat_mean(dict_values(trdD))
    tSd = stat_stddev(dict_values(trdD)) + 0.000001
    qMu = stat_mean(dict_values(rsiD))
    qSd = stat_stddev(dict_values(rsiD)) + 0.000001
    scores = dict_new()
    for (sym in dict_keys(momD)) {
      dict_set(scores, sym,
        (dict_get(momD, sym) - mMu) / mSd * 1.0 +
        (dict_get(revD, sym) - rMu) / rSd * 0.5 +
        (dict_get(trdD, sym) - tMu) / tSd * 0.7 +
        (dict_get(rsiD, sym) - qMu) / qSd * 0.3)
    }
    picks = scan_top(scores, topN)
    rebalance_equal(picks)
  }
}
