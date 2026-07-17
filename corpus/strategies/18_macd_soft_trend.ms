strategy MacdSoftTrend {
  trend = sma(close, 55)
  onBar {
    m = macd(close, 13, 34, 8)
    when close > trend && m.hist > 0: long()
    when m.hist < 0: flat()
    when close < trend: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:07Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: MACD hist>0 above SMA55 (softer trend)
  IS: sharpe=0.2327 mdd=0.3740 ret=0.4828 calmar=1.2908 trades=556 equity=148281.09 bars=6528
  OOS: sharpe=0.8913 mdd=0.0711 ret=0.6639 calmar=9.3340 trades=169 equity=166387.26 bars=1891
  vs_bh_IS: d_sharpe=-0.3252 d_mdd=-0.1778 d_ret=-7.6212
  vs_bh_OOS: d_sharpe=+0.0381 d_mdd=-0.2657 d_ret=-1.3192
  transfers_oos: oos_only
*/
