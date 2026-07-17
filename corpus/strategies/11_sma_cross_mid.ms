strategy SmaCrossMid {
  maFast = sma(close, 13)
  maSlow = sma(close, 34)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:02Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: 13/34 SMA cross medium trend
  IS: sharpe=0.5458 mdd=0.3405 ret=3.1814 calmar=9.3440 trades=184 equity=418136.04 bars=6528
  OOS: sharpe=0.8067 mdd=0.1930 ret=0.9351 calmar=4.8455 trades=48 equity=193514.97 bars=1891
  vs_bh_IS: d_sharpe=-0.0121 d_mdd=-0.2114 d_ret=-4.9227
  vs_bh_OOS: d_sharpe=-0.0466 d_mdd=-0.1438 d_ret=-1.0479
  transfers_oos: is_only
*/
