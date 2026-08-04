// Soften online cuts — smaller steps; DD tighten only raises bullCut (doesn't kill META).

class OnlineCuts {
  bull = 0.28
  bear = 0.22
  calm = 0.018
  deep = -0.05
  peakEq = 0.0
  coolUntil = 0.0
  ddTight = 0.0

  function touchEquity(eq) {
    when peakEq <= 0.0: peakEq = eq
    when eq > peakEq: peakEq = eq
    dd = (peakEq - eq) / (peakEq + 0.0001)
    when dd > 0.04: {
      ddTight = 1.0
      bull = bull + 0.01
      when bull > 0.40: bull = 0.40
    }
    when dd < 0.015: ddTight = 0.0
    return dd
  }

  function learn(ret, barIdx) {
    when ret > 0.0: {
      bull = bull - 0.004
      bear = bear + 0.002
    }
    when ret <= 0.0: {
      bull = bull + 0.008
      bear = bear - 0.004
      coolUntil = barIdx + 2.0
    }
    when bull < 0.18: bull = 0.18
    when bull > 0.40: bull = 0.40
    when bear < 0.10: bear = 0.10
    when bear > 0.30: bear = 0.30
    when calm < 0.012: calm = 0.012
    when calm > 0.024: calm = 0.024
    when deep < -0.10: deep = -0.10
    when deep > -0.02: deep = -0.02
    return bull
  }

  function cooling(barIdx) {
    return barIdx < coolUntil
  }

  function underStress() {
    return ddTight > 0.5
  }
}
