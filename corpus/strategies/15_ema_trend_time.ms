strategy EmaTrendTimeStop {
  fast = ema(close, 13)
  slow = ema(close, 34)
  trend = sma(close, 89)
  onBar {
    when close > trend && crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
    when close < trend: flat()
  }
  onPosition {
    when bars_in_trade >= 55: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:04Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 13/34 + SMA89 filter + 55-bar time stop
  IS: sharpe=0.1538 mdd=0.3277 ret=0.2582 calmar=0.7877 trades=136 equity=125815.61 bars=6528
  OOS: sharpe=0.6164 mdd=0.1155 ret=0.4885 calmar=4.2294 trades=41 equity=148852.94 bars=1891
  vs_bh_IS: d_sharpe=-0.4041 d_mdd=-0.2241 d_ret=-7.8459
  vs_bh_OOS: d_sharpe=-0.2369 d_mdd=-0.2213 d_ret=-1.4945
  transfers_oos: no
*/
