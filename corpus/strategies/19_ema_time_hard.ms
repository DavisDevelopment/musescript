strategy EmaTimeHardStop {
  fast = ema(close, 13)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 55: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:07Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 13/34 time stop + 5% equity hard stop
  IS: sharpe=0.4515 mdd=0.3638 ret=2.1790 calmar=5.9892 trades=182 equity=317900.55 bars=6528
  OOS: sharpe=0.9185 mdd=0.1818 ret=1.1336 calmar=6.2352 trades=53 equity=213361.06 bars=1891
  vs_bh_IS: d_sharpe=-0.1065 d_mdd=-0.1881 d_ret=-5.9250
  vs_bh_OOS: d_sharpe=+0.0652 d_mdd=-0.1550 d_ret=-0.8495
  transfers_oos: yes
*/
