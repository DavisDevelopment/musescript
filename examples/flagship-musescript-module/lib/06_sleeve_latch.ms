// Causal sleeve-mode latch with 3-bar hysteresis.
// Modes: 0=crown, 1=sticky, 2=atr, 3=flip
// Switch only after `need` consecutive bars agree on a new candidate.

class SleeveLatch {
  mode = 0.0
  pending = 0.0
  agree = 0.0
  need = 3.0
  flipped = 0.0

  function observe(c) {
    flipped = 0.0
    when c == mode: {
      pending = c
      agree = 0.0
      return mode
    }
    when c == pending: {
      agree = agree + 1.0
      when agree >= need: {
        mode = c
        agree = 0.0
        flipped = 1.0
      }
      return mode
    }
    pending = c
    agree = 1.0
    return mode
  }

  function is(v) {
    return mode == v
  }

  function get() {
    return mode
  }

  function justFlipped() {
    return flipped > 0.5
  }

  function force(v) {
    mode = v
    pending = v
    agree = 0.0
    flipped = 0.0
    return v
  }
}
