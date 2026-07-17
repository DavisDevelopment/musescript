strategy Sma521 {
  maFast = sma(close, 5)
  maSlow = sma(close, 21)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:54:41Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: SMA 5/21 fast swing cross
  IS: sharpe=0.2659 mdd=0.3617 ret=0.8287 calmar=2.2910 trades=392 equity=182871.20 bars=6528
  OOS: sharpe=1.2303 mdd=0.1614 ret=1.6997 calmar=10.5310 trades=85 equity=269972.44 bars=1891
  vs_bh_IS: d_sharpe=-0.2920 d_mdd=-0.1902 d_ret=-7.2753
  vs_bh_OOS: d_sharpe=+0.3770 d_mdd=-0.1754 d_ret=-0.2833
  transfers_oos: oos_only
*/
