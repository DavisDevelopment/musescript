// S4 — S2's multi-factor z-blend + HYSTERESIS to survive transaction costs.
// A name is kept as long as it stays in the wide retention band (top-45); new names only
// enter via the tight top-15. This slashes turnover vs S2's daily top-15 refresh, so the
// strategy keeps its edge net of realistic per-trade costs.
strategy MultiFactorHysteresis {
  param topN = 15
  param bandMult = 3
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
    entry = scan_top(scores, topN)
    band = scan_top(scores, topN * bandMult)
    keepD = dict_new()
    for (s in band) {
      dict_set(keepD, s, 1)
    }
    targetD = dict_new()
    for (s in holdings()) {
      when dict_has(keepD, s): dict_set(targetD, s, 1)
    }
    for (s in entry) {
      dict_set(targetD, s, 1)
    }
    rebalance_equal(dict_keys(targetD))
  }
}
