strategy RsiMeanRev {
  r = rsi(close, 13)
  onBar {
    when r < 30: long()
    when r > 70: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:57Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: RSI(13) mean-reversion long-only
  IS: sharpe=0.3730 mdd=0.5069 ret=2.0752 calmar=4.0937 trades=133 equity=307515.78 bars=6528
  OOS: sharpe=0.4841 mdd=0.2828 ret=0.6039 calmar=2.1358 trades=44 equity=160390.97 bars=1891
  vs_bh_IS: d_sharpe=-0.1850 d_mdd=-0.0450 d_ret=-6.0289
  vs_bh_OOS: d_sharpe=-0.3691 d_mdd=-0.0540 d_ret=-1.3792
  transfers_oos: no
*/
