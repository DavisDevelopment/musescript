class S extends FlagshipRisk {
  path = new PathLatch()
  function onBar() {
    when position() == 0 && path.get() != 0: path.clear()
    when position() == 0 && bar_index == 5: {
      path.set(2)
      long()
    }
    when path.is(2) && bars_in_trade >= 3: {
      path.clear()
      flat()
    }
  }
  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
