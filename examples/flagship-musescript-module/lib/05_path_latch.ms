// Persistent entry-path latch (construct-once). Lives across bars so exits can
// branch on HOW we got in, not only on the tape right now.
//
// Codes: 0=flat, 1=crown, 2=atr, 3=bounce, 4=macdZero, 5=seed

class PathLatch {
  p = 0.0

  function set(v) {
    p = v
    return v
  }

  function get() {
    return p
  }

  function clear() {
    p = 0.0
    return 0.0
  }

  function is(v) {
    return p == v
  }
}
