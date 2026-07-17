strategy EwmVolRegime {
  param volLen: Window = 21
  param retLook: Window = 34
  vol = ewm_stdev(close, volLen)
  rets = sci_diff(window(close, retLook))
  kurt = stat_kurtosis(rets)
  onBar {
    when vol < sma(close, volLen) * 0.02 && kurt < 1.0 && rising(close, 2): long()
    when vol > sma(close, volLen) * 0.04 || kurt > 3.0: flat()
  }
  onPosition {
    when falling(close, 3): flat()
  }
}
