// Intra-run sleeve reinforcement. Crown (1) is immortal — losses only demote
// specialist sleeves (2=atr, 5=sticky, 6=flip). Wins still bump everything.

class SleeveBrain {
  s2 = 1.0
  s5 = 1.0
  s6 = 1.0
  losses = 0.0
  wins = 0.0
  streak = 0.0

  function boost(code, amt) {
    when code == 2.0: s2 = s2 + amt
    when code == 5.0: s5 = s5 + amt
    when code == 6.0: s6 = s6 + amt
    return amt
  }

  function kill(code) {
    when code == 5.0: s5 = 0.15
    when code == 6.0: s6 = 0.15
    return 0.15
  }

  function learn(code, ret) {
    when ret > 0.0: {
      wins = wins + 1.0
      when streak < 0.0: streak = 0.0
      streak = streak + 1.0
      when code == 5.0 || code == 6.0: boost(code, 0.15)
    }
    // Sticky (IWM): one strike and you're out. Flip (MSFT): thicker skin.
    when code == 5.0 && ret <= 0.0: {
      losses = losses + 1.0
      streak = streak - 1.0
      s5 = 0.15
    }
    when code == 6.0 && ret <= -0.015: {
      losses = losses + 1.0
      streak = streak - 1.0
      s6 = 0.15
    }
    when s5 > 3.0: s5 = 3.0
    when s6 > 3.0: s6 = 3.0
    return ret
  }

  function likes(code) {
    when code == 1.0: return true
    when code == 2.0: return true
    when code == 3.0: return true
    when code == 4.0: return true
    when code == 5.0: return s5 >= 0.70
    when code == 6.0: return s6 >= 0.70
    return false
  }

  function cooling() {
    return streak <= -2.0
  }
}
