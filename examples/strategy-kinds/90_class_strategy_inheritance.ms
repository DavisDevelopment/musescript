// Class-shaped strategies: `class X extends muse.Strat`.
//
// The whole point is the base class. `template` and `module` compose by expansion, so sharing
// exit logic across strategies means every one of them repeats the call. A base class lets the
// shared behaviour live in one place and lets a subclass replace just the piece it disagrees
// with — here, RiskManaged owns the exits and each strategy owns only its entry.
//
// Inheritance is resolved at compile time (see ClassStrategyLower), so this reaches the backends
// as three ordinary strategies and runs on the same compiled path as the `strategy` surface.

class RiskManaged extends muse.Strat {
  param stopPct: Scalar = 0.05
  param maxBars: Window = 21

  function stopped() { return unrealized_pnl_pct() < -stopPct }
  function staleTrade() { return bars_in_trade() > maxBars }

  function onPosition() {
    when stopped() || staleTrade(): flat()
  }
}

class MaCrossover extends RiskManaged {
  param fast: Window = 8
  param slow: Window = 34

  f = sma(close, fast)
  s = sma(close, slow)

  function onBar() {
    when crossover(f, s): long()
    when crossunder(f, s): flat()
  }
}

class RsiReversion extends RiskManaged {
  param len: Window = 13

  r = rsi(close, len)

  function onBar() {
    when r < 30: long()
    when r > 70: flat()
  }
}

// A subclass may tighten inherited behaviour. `super.stopped()` keeps the base's rule and adds
// to it, rather than restating it — the base's body is spliced in where the call sits.
class TightMaCrossover extends MaCrossover {
  function stopped() { return super.stopped() || close < lowest(low, 5) }
}
