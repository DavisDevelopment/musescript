strategy DonchianTrend {
  trend = sma(close, 89)
  onBar {
    when close > trend && close >= highest(high, 21): long()
    when close <= lowest(low, 13): flat()
    when close < trend: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:03Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: Donchian 21 breakout only above SMA89
  IS: sharpe=0.2521 mdd=0.2203 ret=0.5155 calmar=2.3402 trades=60 equity=151547.00 bars=6528
  OOS: sharpe=0.1524 mdd=0.1422 ret=0.0662 calmar=0.4659 trades=18 equity=106624.38 bars=1891
  vs_bh_IS: d_sharpe=-0.3058 d_mdd=-0.3316 d_ret=-7.5886
  vs_bh_OOS: d_sharpe=-0.7008 d_mdd=-0.1946 d_ret=-1.9168
  transfers_oos: no
*/
