// flagship_bull — sticky-ride twin for bull walk-forwards (2019 / 2024q4).
// Matrix champion stays flagship_v6l. This genome is scored via harness/bull_score.py.
// DNA: bar1 long seed, late RSI fade, deep underwater handoff (IWM-style).

class FlagshipBull extends FlagshipRisk {
  primed = new PathLatch()
  ride = new PathLatch()

  r5 = rsi(close, 5)

  function onBar() {
    when bar_index == 1 && primed.get() < 0.5: {
      ride.set(1)
      long()
      primed.set(1)
    }

    when ride.is(1) && bar_index >= 55 && r5 < 45: {
      ride.clear()
      flat()
    }
    when ride.is(1) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {
      ride.clear()
      flat()
    }
  }
}
