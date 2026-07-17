strategy RsiDipTrend {
  r = rsi(close, 13)
  trend = sma(close, 89)
  onBar {
    when close > trend && r < 35: long()
    when r > 65: flat()
    when close < trend: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:55:57Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: RSI dips only while price above SMA89
  IS: sharpe=0.1239 mdd=0.2603 ret=0.1313 calmar=0.5044 trades=122 equity=113129.69 bars=6528
  OOS: sharpe=0.4097 mdd=0.1156 ret=0.1694 calmar=1.4659 trades=48 equity=116943.74 bars=1891
  vs_bh_IS: d_sharpe=-0.4340 d_mdd=-0.2916 d_ret=-7.9727
  vs_bh_OOS: d_sharpe=-0.4435 d_mdd=-0.2212 d_ret=-1.8136
  transfers_oos: no
*/
