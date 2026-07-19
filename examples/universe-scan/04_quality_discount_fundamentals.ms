// S5 — "Quality on discount": gate 03's price-discount z-blend (trend momentum +
// short-term pullback) behind a Piotroski-lite fundamentals screen built from real
// point-in-time SEC/EDGAR facts (fund_of): the name must be profitable, growing
// revenue, and have cash flow backing its earnings (no accrual games) as of what
// the market actually knew on that bar — never period-end, always filing_date.
// Same wide-band hysteresis as 03 to keep turnover low.
strategy QualityDiscount {
  param topN = 15
  param bandMult = 3
  param trendLook = 200

  onBar {
    momD = dict_new()
    revD = dict_new()
    trdD = dict_new()
    for (sym in symbols()) {
      ni = fund_of(sym, "net_income_fy")
      rg = fund_of(sym, "revenue_growth")
      ocf = fund_of(sym, "operating_cash_flow_fy")
      when sym_available(sym) && close_of(sym) > sma_of(sym, trendLook)
        && !na(ni) && ni > 0
        && !na(rg) && rg > 0
        && !na(ocf) && ocf > ni: {
        dict_set(momD, sym, mom_of(sym, 126))
        dict_set(revD, sym, 0 - mom_of(sym, 5))
        dict_set(trdD, sym, close_of(sym) / sma_of(sym, 50) - 1)
      }
    }
    mMu = stat_mean(dict_values(momD))
    mSd = stat_stddev(dict_values(momD)) + 0.000001
    rMu = stat_mean(dict_values(revD))
    rSd = stat_stddev(dict_values(revD)) + 0.000001
    tMu = stat_mean(dict_values(trdD))
    tSd = stat_stddev(dict_values(trdD)) + 0.000001
    scores = dict_new()
    for (sym in dict_keys(momD)) {
      dict_set(scores, sym,
        (dict_get(momD, sym) - mMu) / mSd * 1.0 +
        (dict_get(revD, sym) - rMu) / rSd * 0.5 +
        (dict_get(trdD, sym) - tMu) / tSd * 0.7)
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
