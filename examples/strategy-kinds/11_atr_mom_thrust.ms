strategy AtrMomThrust {
  param momLen: Window = 13
  param atrLen: Window = 13
  thrust = mom(close, momLen)
  vol = atr(close, atrLen)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when thrust < 0 || roc(close, momLen) < -1: flat()
  }
  onPosition {
    when falling(thrust, 3, 5): flat()
  }
}
