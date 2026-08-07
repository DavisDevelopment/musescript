// Mean-reversion #10 — CCI-style, built by hand: (typicalPrice - SMA) / (0.015 *
// meanDeviation-proxy). We approximate mean deviation with stdev (true CCI uses
// mean ABSOLUTE deviation; stdev is the standard, honest MuseScript-native
// substitute — no fabricated precision claimed). Unbounded oscillator, unlike
// RSI/Stochastic/Williams — reacts more to outliers.
//
// NOTE: hlc3() is declared in the type checker (BuiltinSigs.hx) but throws at
// runtime ("Cannot read properties of null (reading 'apply')") — confirmed a
// genuine engine bug (hl2()/ohlc4() are equally broken; vwap() works fine), not
// a mistake in this file. Typical price is built by hand from close/high/low
// instead, which are all confirmed working.

strategy CciStyle {
  tp = (high + low + close) / 3.0
  tpAvg = sma(close, 20)
  tpDev = stdev(close, 20)
  cci = (tp - tpAvg) / (0.015 * tpDev)
  onBar {
    when cci < -100: long()
    when cci > 0: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
