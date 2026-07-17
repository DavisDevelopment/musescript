strategy ema_8_13_ex21_tx {
  fast = ema(close, 8)
  slow = ema(close, 13)
  exitMa = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, exitMa): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:53:34Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/13 exit vs EMA21
  IS: sharpe=0.3260 mdd=0.4740 ret=1.3432 calmar=2.8340 trades=296 equity=234322.41 bars=6528
  OOS: sharpe=1.2646 mdd=0.1732 ret=2.0145 calmar=11.6295 trades=63 equity=301446.85 bars=1891
  vs_bh_IS: d_sharpe=-0.2320 d_mdd=-0.0779 d_ret=-6.7608
  vs_bh_OOS: d_sharpe=+0.4114 d_mdd=-0.1636 d_ret=+0.0314
  transfers_oos: oos_only
  notes: sweep rank; late sharpe=1.0870
*/
