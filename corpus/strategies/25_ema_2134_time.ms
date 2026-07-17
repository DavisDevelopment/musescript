strategy Ema2134Time {
  fast = ema(close, 21)
  slow = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 34: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:10Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 21/34 with 34-bar time stop
  IS: sharpe=0.6493 mdd=0.3559 ret=4.8666 calmar=13.6755 trades=132 equity=586659.96 bars=6528
  OOS: sharpe=0.8215 mdd=0.2547 ret=0.9995 calmar=3.9243 trades=39 equity=199949.36 bars=1891
  vs_bh_IS: d_sharpe=+0.0914 d_mdd=-0.1960 d_ret=-3.2374
  vs_bh_OOS: d_sharpe=-0.0318 d_mdd=-0.0821 d_ret=-0.9836
  transfers_oos: is_only
*/
