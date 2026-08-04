// Probe: confirm PathLatch survives next-open fill on IWM.
class ProbePathSticky extends muse.Strat {
  path = new PathLatch()
  r5 = rsi(close, 5)

  function onBar() {
    when symbol_is("IWM") && bar_index == 1: {
      path.set(5)
      long()
    }
    // Force flat + plot path when first red
    when path.is(5) && bars_in_trade >= 1 && unrealized_pnl < -0.005 * equity: {
      path.set(9)
      flat()
    }
    when (!path.is(5)) && (!path.is(9)) && bar_index == 5: {
      // path lost → mark
      path.set(7)
    }
    when path.is(9) && bar_index >= 10: flat()
    when path.is(5) && bar_index >= 55 && r5 < 45: flat()
  }
}
