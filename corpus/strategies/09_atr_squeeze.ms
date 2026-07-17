strategy AtrSqueezeBreakout {
  atrFast = atr(close, 13)
  atrSlow = atr(close, 55)
  onBar {
    when atrFast < atrSlow * 0.85 && close >= highest(high, 21): long()
    when close < sma(close, 21): flat()
  }
}

/* CORPUS_BACKTEST
  generated: 2026-07-16T04:56:01Z
  tape_is: spy_is_1993_2018 (<= 2018-12-31)
  tape_oos: spy_oos_2019_2026 (>= 2019-01-01)
  hypothesis: ATR compression then 21d breakout
  IS: sharpe=0.0969 mdd=0.1203 ret=0.0583 calmar=0.4845 trades=34 equity=105826.95 bars=6528
  OOS: sharpe=-0.3686 mdd=0.1343 ret=-0.0857 calmar=-0.6381 trades=14 equity=91431.83 bars=1891
  vs_bh_IS: d_sharpe=-0.4610 d_mdd=-0.4316 d_ret=-8.0458
  vs_bh_OOS: d_sharpe=-1.2219 d_mdd=-0.2025 d_ret=-2.0687
  transfers_oos: no
*/
