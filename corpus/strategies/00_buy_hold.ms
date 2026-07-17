strategy BuyHold {
  onBar {
    when bar_index == 55: long()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:56Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: Baseline buy-and-hold from bar 55
  IS: sharpe=0.5579 mdd=0.5519 ret=8.1040 calmar=14.6845 trades=1 equity=910404.59 bars=6528
  OOS: sharpe=0.8533 mdd=0.3368 ret=1.9831 calmar=5.8880 trades=1 equity=298306.76 bars=1891
  vs_bh_IS: d_sharpe=+0.0000 d_mdd=+0.0000 d_ret=+0.0000
  vs_bh_OOS: d_sharpe=+0.0000 d_mdd=+0.0000 d_ret=+0.0000
  transfers_oos: is_only
*/
