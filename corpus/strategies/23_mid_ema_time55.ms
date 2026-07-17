strategy MidEmaTime55 {
  fast = ema(close, 13)
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
  generated: 2026-07-16T04:56:09Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: EMA 13/21 with 55-bar time stop
  IS: sharpe=0.3940 mdd=0.3137 ret=1.6314 calmar=5.2011 trades=248 equity=263144.07 bars=6528
  OOS: sharpe=1.1166 mdd=0.1231 ret=1.5421 calmar=12.5307 trades=49 equity=254207.54 bars=1891
  vs_bh_IS: d_sharpe=-0.1639 d_mdd=-0.2382 d_ret=-6.4726
  vs_bh_OOS: d_sharpe=+0.2633 d_mdd=-0.2137 d_ret=-0.4410
  transfers_oos: yes
  notes: late_oos_2022+: sharpe=1.1154 mdd=0.1017 ret=0.6717 (bh_late sharpe~0.85 mdd~0.22)
*/
