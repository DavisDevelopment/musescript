strategy GoldenCross {
  maFast = sma(close, 55)
  maSlow = sma(close, 89)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:57Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: Fib 55/89 SMA golden cross trend follow
  IS: sharpe=0.7063 mdd=0.2109 ret=6.6012 calmar=31.3037 trades=60 equity=760115.33 bars=6528
  OOS: sharpe=0.4677 mdd=0.3418 ret=0.5323 calmar=1.5572 trades=13 equity=153232.20 bars=1891
  vs_bh_IS: d_sharpe=+0.1484 d_mdd=-0.3410 d_ret=-1.5029
  vs_bh_OOS: d_sharpe=-0.3855 d_mdd=+0.0051 d_ret=-1.4507
  transfers_oos: is_only
*/
