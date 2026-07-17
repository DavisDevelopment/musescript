strategy FastEmaLongTime {
  fast = ema(close, 8)
  slow = ema(close, 21)
  onBar {
    when crossover(fast, slow): long()
    when crossunder(fast, slow): flat()
  }
  onPosition {
    when bars_in_trade >= 55: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:08Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 8/21 with 55-bar time stop
  IS: sharpe=0.3385 mdd=0.3382 ret=1.2416 calmar=3.6714 trades=314 equity=224157.21 bars=6528
  OOS: sharpe=1.1610 mdd=0.1429 ret=1.6206 calmar=11.3406 trades=65 equity=262059.44 bars=1891
  vs_bh_IS: d_sharpe=-0.2195 d_mdd=-0.2137 d_ret=-6.8625
  vs_bh_OOS: d_sharpe=+0.3077 d_mdd=-0.1939 d_ret=-0.3625
  transfers_oos: oos_only
*/
