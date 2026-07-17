strategy MacdAboveTrend {
  trend = sma(close, 89)
  onBar {
    m = macd(close, 13, 34, 8)
    when close > trend && m.hist > 0: long()
    when m.hist < 0: flat()
    when close < trend: flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:04Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: MACD hist>0 only above SMA89
  IS: sharpe=0.1646 mdd=0.3775 ret=0.2753 calmar=0.7293 trades=548 equity=127528.30 bars=6528
  OOS: sharpe=0.8501 mdd=0.0978 ret=0.5864 calmar=5.9940 trades=153 equity=158638.33 bars=1891
  vs_bh_IS: d_sharpe=-0.3933 d_mdd=-0.1744 d_ret=-7.8288
  vs_bh_OOS: d_sharpe=-0.0031 d_mdd=-0.2390 d_ret=-1.3967
  transfers_oos: no
*/
