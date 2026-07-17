strategy ema_8_13_tx {
  fast = ema(close, 8)
  slow = ema(close, 13)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:53:35Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/13
  IS: sharpe=0.1894 mdd=0.4137 ret=0.4676 calmar=1.1303 trades=398 equity=146764.00 bars=6528
  OOS: sharpe=1.2406 mdd=0.1695 ret=1.7395 calmar=10.2601 trades=85 equity=273949.34 bars=1891
  vs_bh_IS: d_sharpe=-0.3685 d_mdd=-0.1381 d_ret=-7.6364
  vs_bh_OOS: d_sharpe=+0.3873 d_mdd=-0.1673 d_ret=-0.2436
  transfers_oos: oos_only
  notes: sweep rank; late sharpe=0.9608
*/
