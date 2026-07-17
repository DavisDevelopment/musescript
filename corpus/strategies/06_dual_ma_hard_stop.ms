strategy DualMaHardStop {
  maFast = sma(close, 21)
  maSlow = sma(close, 55)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
  onPosition {
    when unrealized_pnl < -0.08 * equity: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:58Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: 21/55 SMA cross with 8% equity hard stop
  IS: sharpe=0.4197 mdd=0.4035 ret=2.0093 calmar=4.9798 trades=128 equity=300933.44 bars=6528
  OOS: sharpe=0.7221 mdd=0.2638 ret=0.8444 calmar=3.2011 trades=31 equity=184436.44 bars=1891
  vs_bh_IS: d_sharpe=-0.1383 d_mdd=-0.1484 d_ret=-6.0947
  vs_bh_OOS: d_sharpe=-0.1311 d_mdd=-0.0730 d_ret=-1.1387
  transfers_oos: no
*/
