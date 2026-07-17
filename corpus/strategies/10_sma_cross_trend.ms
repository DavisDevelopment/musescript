strategy SmaCrossTrendFilter {
  maFast = sma(close, 8)
  maSlow = sma(close, 21)
  trend = sma(close, 89)
  onBar {
    when close > trend && crossover(maFast, maSlow): long()
    when crossunder(maFast, maSlow): flat()
    when close < trend: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:02Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: 8/21 SMA cross only above SMA89 trend filter
  IS: sharpe=0.2520 mdd=0.2719 ret=0.5191 calmar=1.9093 trades=244 equity=151914.82 bars=6528
  OOS: sharpe=0.7039 mdd=0.1277 ret=0.5293 calmar=4.1454 trades=61 equity=152927.55 bars=1891
  vs_bh_IS: d_sharpe=-0.3059 d_mdd=-0.2800 d_ret=-7.5849
  vs_bh_OOS: d_sharpe=-0.1494 d_mdd=-0.2091 d_ret=-1.4538
  transfers_oos: no
*/
