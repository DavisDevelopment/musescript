strategy Ema834 {
  fast = ema(close, 8)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:54:20Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/34 — best IS+OOS balance from sweep
  IS: sharpe=0.3757 mdd=0.4244 ret=1.5108 calmar=3.5598 trades=236 equity=251076.61 bars=6528
  OOS: sharpe=1.1751 mdd=0.1177 ret=1.6997 calmar=14.4404 trades=45 equity=269971.02 bars=1891
  vs_bh_IS: d_sharpe=-0.1823 d_mdd=-0.1275 d_ret=-6.5933
  vs_bh_OOS: d_sharpe=+0.3218 d_mdd=-0.2191 d_ret=-0.2834
  transfers_oos: yes
*/
