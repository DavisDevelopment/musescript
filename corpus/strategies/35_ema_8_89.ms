strategy Ema889 {
  fast = ema(close, 8)
  slow = ema(close, 89)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:54:40Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/89 slow trend cross
  IS: sharpe=0.6597 mdd=0.4072 ret=5.2346 calmar=12.8544 trades=118 equity=623462.38 bars=6528
  OOS: sharpe=1.0992 mdd=0.2016 ret=1.6049 calmar=7.9597 trades=27 equity=260487.21 bars=1891
  vs_bh_IS: d_sharpe=+0.1017 d_mdd=-0.1447 d_ret=-2.8694
  vs_bh_OOS: d_sharpe=+0.2460 d_mdd=-0.1352 d_ret=-0.3782
  transfers_oos: yes
*/
