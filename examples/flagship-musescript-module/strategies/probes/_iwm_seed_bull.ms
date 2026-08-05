// Minimal IWM seed probe
class FlagshipIwmSeedProbe extends FlagshipRisk {
  primed = new PathLatch()
  stickyGate = new PathLatch()
  r5 = rsi(close, 5)

  function onBar() {
    when symbol_is("IWM") && bar_index == 1 && primed.get() < 0.5: {
      stickyGate.set(1)
      long()
      primed.set(1)
    }
    when stickyGate.is(1) && bar_index >= 55 && r5 < 45: {
      stickyGate.clear()
      flat()
    }
  }
  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
