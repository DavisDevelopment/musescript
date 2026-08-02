// Compile-time class metaprogramming: ClassStrategyLower flattens this into a
// StrategyDecl before emit. Subclasses override helpers via super.* splicing.

class FlagshipRisk extends muse.Strat {
  param stopPct: Scalar = 0.05 { min: 0.03, max: 0.08, step: 0.01, tune: grid }
  param timeBars: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param lockBars: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param lockPct: Scalar = 0.03 { min: 0.02, max: 0.05, step: 0.01, tune: grid }

  function hardStopped() {
    return unrealized_pnl < -stopPct * equity
  }

  function timedOut() {
    return bars_in_trade >= timeBars
  }

  function profitLocked() {
    return bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): flat()
  }
}
