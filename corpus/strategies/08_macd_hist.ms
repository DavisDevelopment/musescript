strategy MacdHistRegime {
  onBar {
    m = macd(close, 13, 34, 8)
    when m.hist > 0: long()
    when m.hist < 0: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:00Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: MACD histogram regime (long when hist>0)
  IS: sharpe=0.3074 mdd=0.3569 ret=1.0466 calmar=2.9321 trades=542 equity=204658.52 bars=6528
  OOS: sharpe=0.7919 mdd=0.1849 ret=0.8196 calmar=4.4322 trades=171 equity=181962.01 bars=1891
  vs_bh_IS: d_sharpe=-0.2506 d_mdd=-0.1949 d_ret=-7.0575
  vs_bh_OOS: d_sharpe=-0.0613 d_mdd=-0.1519 d_ret=-1.1634
  transfers_oos: no
*/
