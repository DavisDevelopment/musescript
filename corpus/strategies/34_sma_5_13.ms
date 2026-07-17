strategy Sma513 {
  maFast = sma(close, 5)
  maSlow = sma(close, 13)
  onBar {
    when crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T08:54:20Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: SMA 5/13 faster variant
  IS: sharpe=0.0267 mdd=0.5811 ret=-0.0846 calmar=-0.1457 trades=588 equity=91535.26 bars=6528
  OOS: sharpe=1.0612 mdd=0.1619 ret=1.3241 calmar=8.1770 trades=137 equity=232410.83 bars=1891
  vs_bh_IS: d_sharpe=-0.5312 d_mdd=+0.0292 d_ret=-8.1887
  vs_bh_OOS: d_sharpe=+0.2080 d_mdd=-0.1749 d_ret=-0.6590
  transfers_oos: oos_only
*/
