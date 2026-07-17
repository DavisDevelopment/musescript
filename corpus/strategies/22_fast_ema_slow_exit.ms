strategy FastEmaSlowExit {
  fast = ema(close, 8)
  slow = ema(close, 21)
  exitMa = ema(close, 34)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, exitMa): flat()
  }
  onPosition {
    when bars_in_trade >= 55: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:09Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/21 entry, exit vs EMA34 + time stop
  IS: sharpe=0.3435 mdd=0.4674 ret=1.4861 calmar=3.1798 trades=223 equity=248614.84 bars=6528
  OOS: sharpe=1.1151 mdd=0.1850 ret=1.6913 calmar=9.1412 trades=45 equity=269126.56 bars=1891
  vs_bh_IS: d_sharpe=-0.2145 d_mdd=-0.0845 d_ret=-6.6179
  vs_bh_OOS: d_sharpe=+0.2618 d_mdd=-0.1518 d_ret=-0.2918
  transfers_oos: oos_only
*/
