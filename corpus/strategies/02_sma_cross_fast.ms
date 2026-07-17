strategy SmaCrossFast {
  maFast = sma(close, 8)
  maSlow = sma(close, 21)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:57Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: Fast 8/21 SMA cross for medium swings
  IS: sharpe=0.4269 mdd=0.2353 ret=1.9800 calmar=8.4151 trades=342 equity=298001.12 bars=6528
  OOS: sharpe=0.9168 mdd=0.1979 ret=1.1227 calmar=5.6727 trades=79 equity=212268.01 bars=1891
  vs_bh_IS: d_sharpe=-0.1310 d_mdd=-0.3166 d_ret=-6.1240
  vs_bh_OOS: d_sharpe=+0.0636 d_mdd=-0.1389 d_ret=-0.8604
  transfers_oos: oos_only
*/
