strategy sma_8_13_tx {
  maFast = sma(close, 8)
  maSlow = sma(close, 13)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:53:34Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: SMA 8/13
  IS: sharpe=0.1240 mdd=0.4377 ret=0.2184 calmar=0.4990 trades=598 equity=121841.11 bars=6528
  OOS: sharpe=1.2724 mdd=0.1264 ret=1.8501 calmar=14.6403 trades=151 equity=285005.25 bars=1891
  vs_bh_IS: d_sharpe=-0.4340 d_mdd=-0.1142 d_ret=-7.8856
  vs_bh_OOS: d_sharpe=+0.4191 d_mdd=-0.2104 d_ret=-0.1330
  transfers_oos: oos_only
  notes: sweep rank; late sharpe=1.3001
*/
