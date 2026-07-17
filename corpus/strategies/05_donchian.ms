strategy DonchianBreakout {
  onBar {
    when close >= highest(high, 21): long()
    when close <= lowest(low, 8): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:58Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: Donchian 21-high entry / 8-low exit
  IS: sharpe=0.2703 mdd=0.5853 ret=1.1451 calmar=1.9563 trades=47 equity=214505.59 bars=6528
  OOS: sharpe=0.7837 mdd=0.2172 ret=1.0199 calmar=4.6958 trades=7 equity=201987.56 bars=1891
  vs_bh_IS: d_sharpe=-0.2877 d_mdd=+0.0334 d_ret=-6.9590
  vs_bh_OOS: d_sharpe=-0.0696 d_mdd=-0.1196 d_ret=-0.9632
  transfers_oos: no
*/
