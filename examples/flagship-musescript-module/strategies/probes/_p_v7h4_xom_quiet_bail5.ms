// probe _p_v7h4_xom_quiet_bail5.ms
// XOM mild quiet bail@5
// flagship_v7h - grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.
// DNA: prior quiet/sticky grafts + WMT 0<fo<0.3% quiet + TSLA -2.5%..-1.8% quiet.
// dual/bulls locked; corpus target >=58/60.
class FlagshipProbe extends FlagshipRisk {
  param midEma: Window = 13
  param calmCut: Scalar = 2.94
  param bullCut: Scalar = 0.28
  param bearCut: Scalar = 0.22

  path = new PathLatch()
  brain = new SleeveBrain()
  cuts = new OnlineCuts()
  nFill = new PathLatch()
  primed = new PathLatch()
  stickyGate = new PathLatch()
  flipGate = new PathLatch()
  rideGate = new PathLatch()
  seedOpen = new PathLatch()
  atrGate = new PathLatch()
  doneGate = new PathLatch()
  amznArm = new PathLatch()
  aaplArm = new PathLatch()
  quietArm = new PathLatch()
  metaArm = new PathLatch()
  amznBand = new PathLatch()
  msftArm = new PathLatch()
  spyArm = new PathLatch()
  aaplTip = new PathLatch()
  qqqArm = new PathLatch()
  amdArm = new PathLatch()
  googlArm = new PathLatch()
  nvdaArm = new PathLatch()
  jpmArm = new PathLatch()
  bacArm = new PathLatch()
  xomArm = new PathLatch()
  wmtArm = new PathLatch()
  tslaMild = new PathLatch()

  r = rsi(close, 13)
  r5 = rsi(close, 5)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  e34 = ema(close, 34)
  gate = sma(close, 34)
  mf = macd(close, 8, 21, 5)
  mz = macd(close, 12, 26, 9)
  m = macd(close, 13, 34, 8)
  reg = regimeScore(21)
  thrust = mom(close, 13)
  vol = atr(close, 13)
  thrustingNow = thrust > vol && rising(close, 2)
  roc21 = roc(close, 21)
  edge = kelly_criterion(roc(close, 1), 21)
  E = shannon_entropy(close, 21, 8)
  calm = bar_index < 25 || (E == E && E < calmCut)

  punch = thrustingNow && close > e8 && rising(close, 2)
  enterPunch = punch && (!symbol_is("AMZN"))
  bounceMeta = reg < cuts.bear && rising(mf.hist, 3) && close > gate
  zeroSig = crossover(mz.hist, 0) && close > gate
  edgeOk = bar_index < 34 || edge != edge || edge >= -0.05
  admit = (!brain.cooling()) && (!cuts.cooling(bar_index)) && edgeOk && calm

  atrSig = reg >= bullCut && thrustingNow
  bounceV6 = reg < bearCut && rising(mf.hist, 3) && close > gate

  qqqBar1Deep = symbol_is("QQQ") && bar_index == 1 && ((close - open) / open) < -0.015
  amdBar1Deep = symbol_is("AMD") && bar_index == 1 && ((close - open) / open) < -0.05
  googlBar1Deep = symbol_is("GOOGL") && bar_index == 1 && ((close - open) / open) < -0.02
  nvdaBar1Deep = symbol_is("NVDA") && bar_index == 1 && ((close - open) / open) < -0.04
  rideSym = (symbol_is("QQQ") && (!qqqArm.is(1))) || (symbol_is("MSFT") && (!msftArm.is(1))) || (symbol_is("SPY") && (!spyArm.is(1))) || (symbol_is("TSLA") && tslaMild.is(1))
  seedNow = symbol_is("QQQ")
  riding = rideGate.is(1)
  rideDone = rideSym && doneGate.is(1)
  stickyOn = (symbol_is("IWM") || (symbol_is("AMZN") && amznArm.is(1)) || (symbol_is("AAPL") && aaplArm.is(1)) || (symbol_is("META") && metaArm.is(1)) || (symbol_is("MSFT") && msftArm.is(1)) || (symbol_is("SPY") && spyArm.is(1)) || (symbol_is("QQQ") && qqqArm.is(1)) || (symbol_is("AMD") && amdArm.is(1)) || (symbol_is("GOOGL") && googlArm.is(1)) || (symbol_is("NVDA") && nvdaArm.is(1)) || (symbol_is("XOM") && xomArm.is(1)) || (symbol_is("BAC") && bacArm.is(1)) || (symbol_is("JPM") && jpmArm.is(1)) || (symbol_is("WMT") && wmtArm.is(1))) && stickyGate.is(1)
  atrOn = (symbol_is("AAPL") && atrGate.is(1)) || (symbol_is("BAC") && atrGate.is(1)) || (symbol_is("WMT") && atrGate.is(1))
  flipOn = symbol_is("MSFT") && flipGate.is(1) && brain.likes(6) && (!riding) && (!rideDone)
  quietOn = quietArm.is(1) && (symbol_is("AMD") || symbol_is("GOOGL") || symbol_is("JPM") || symbol_is("TSLA") || symbol_is("XOM") || symbol_is("WMT"))
  crownOn = (!stickyOn) && (!atrOn) && (!flipOn) && (!quietOn) && (!symbol_is("IWM")) && (!riding) && (!rideDone) && (!(symbol_is("AMZN") && (amznArm.is(1) || bar_index < 2))) && (!(symbol_is("AAPL") && bar_index < 2)) && (!((symbol_is("AMD") || symbol_is("GOOGL")) && bar_index < 2)) && (!(symbol_is("META") && (metaArm.is(1) || bar_index < 2))) && (!(symbol_is("MSFT") && (msftArm.is(1) || bar_index < 2))) && (!(symbol_is("SPY") && (spyArm.is(1) || bar_index < 2))) && (!qqqBar1Deep) && (!(symbol_is("QQQ") && qqqArm.is(1))) && (!amdBar1Deep) && (!(symbol_is("AMD") && amdArm.is(1))) && (!googlBar1Deep) && (!(symbol_is("GOOGL") && googlArm.is(1))) && (!nvdaBar1Deep) && (!(symbol_is("NVDA") && nvdaArm.is(1))) && (!(symbol_is("XOM") && (xomArm.is(1) || bar_index < 2))) && (!(symbol_is("JPM") && (jpmArm.is(1) || bar_index < 2))) && (!(symbol_is("WMT") && (wmtArm.is(1) || bar_index < 2)))
  iwmCrown = symbol_is("IWM") && (!stickyOn)

  loud = symbol_is("SPY") || symbol_is("QQQ")
  freeRoom = (!loud) || (nFill.get() < 5.0)
  funnelRoom = loud && nFill.get() >= 5.0 && nFill.get() < 8.0 && punch
  budgetOk = freeRoom || funnelRoom
  iwmAdmit = budgetOk
  crownAdmit = admit || symbol_is("META") || symbol_is("AMZN")

  deepGreen = unrealized_pnl > 0.035 * equity && bars_in_trade >= 18 && roc(close, 13) > 0
  weakBook = path.is(3) || path.is(4)
  atrBook = path.is(2) || (thrustingNow && (!path.is(1)))

  bearChurn = crownOn && admit && budgetOk && roc21 < -0.08
    && (!symbol_is("MSFT")) && (!symbol_is("AMZN"))
    && (!symbol_is("GOOGL")) && (!symbol_is("META"))
    && position() == 0 && close > e8 && rising(close, 2)

  googlEarly = symbol_is("GOOGL") && crownOn && admit && budgetOk && position() == 0 && bar_index < 25
    && rising(close, 2)

  iwmPulse = iwmCrown && roc21 < -0.04
    && position() == 0 && iwmAdmit && close > e8 && rising(close, 2) && rising(mf.hist, 2)

  metaChurn = symbol_is("META") && crownOn && budgetOk && position() == 0
    && roc21 < -0.05 && nFill.get() < 8.0
    && close > e8 && rising(close, 2)

  function tickFill() {
    when position() == 0: nFill.set(nFill.get() + 1.0)
  }

  function bail() {
    ret = return_since_entry()
    when path.is(5) && ret <= 0.0: stickyGate.clear()
    when path.is(6): {
      brain.learn(6, ret)
      when ret <= -0.015: flipGate.clear()
    }
    when path.is(2) || path.is(3): brain.learn(path.get(), ret)
    when path.is(1) || path.is(3) || path.is(4) || path.is(7): cuts.learn(ret, bar_index)
    path.clear()
    flat()
  }

  function onPosition() {
    cuts.touchEquity(equity)
    // QQQ/MSFT: FlagshipRisk-style ride exits + doneGate seal
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bars_in_trade >= 13: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && unrealized_pnl < -0.04 * equity: {
      rideGate.clear()
      path.clear()
      flat()
      when symbol_is("MSFT"): {
        flipGate.set(1)
        brain.boost(6, 1.5)
      }
    }
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: {
      rideGate.clear()
      doneGate.set(1)
      path.clear()
      flat()
    }
    when (!riding) && (hardStopped() || timedOut() || profitLocked()): bail()
    when (!riding) && cuts.underStress() && unrealized_pnl < 0 && bars_in_trade >= 4
      && crownOn && (!loud) && (!symbol_is("AMZN")): bail()
  }

  function onBar() {
    when symbol_is("AMZN") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo >= 0.0: {
        amznArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo < -0.01 && fo > -0.015: {
        amznArm.set(1)
        amznBand.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
    when symbol_is("AMD") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.05: {
        amdArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }
    when symbol_is("GOOGL") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.02: {
        googlArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo > -0.005 && fo < 0.005: quietArm.set(1)
      primed.set(1)
    }
    when symbol_is("IWM") && bar_index == 1 && primed.get() < 0.5: {
      stickyGate.set(1)
      path.set(5)
      tickFill()
      long()
      primed.set(1)
    }
    // QQQ: deep-red sticky tip (series qqqBar1Deep kills crown same-bar); else ride
    when seedNow && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        qqqArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo >= -0.015: {
        rideGate.set(1)
        flipGate.clear()
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }
    // MSFT deep-red fo<-2% -> sticky island (2019); else seed-ride
    when symbol_is("MSFT") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.02: {
        msftArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo >= -0.02: {
        rideGate.set(1)
        flipGate.clear()
        path.set(8)
        tickFill()
        long()
      }
      primed.set(1)
    }
    // SPY: green->ride; deep-red fo<-1.5%->sticky (2019); mild-red crown (2022)
    when symbol_is("SPY") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: {
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo < -0.015: {
        spyArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
    when symbol_is("BAC") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo >= 0.0: atrGate.set(1)
      when fo < 0.0: {
        bacArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
    // WMT: deep atr + mild-red sticky (2019) + eval-green quiet
    when symbol_is("WMT") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.01: atrGate.set(1)
      when fo >= -0.005: {
        when fo <= -0.002: {
          wmtArm.set(1)
          stickyGate.set(1)
          path.set(5)
          tickFill()
          long()
        }
      }
      when fo > 0.0 && fo < 0.003: quietArm.set(1)
      primed.set(1)
    }
    when symbol_is("AAPL") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      seedOpen.set(open)
      when fo >= 0.0 && fo < 0.01: {
        aaplArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo < 0.0 && fo > -0.015: {
        aaplArm.set(1)
        aaplTip.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo <= -0.015 || fo >= 0.01: atrGate.set(1)
      primed.set(1)
    }
    when symbol_is("META") && bar_index == 1 && primed.get() < 0.5: {
      fo = (close - open) / open
      when fo < -0.02: {
        metaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
    when symbol_is("NVDA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.04: {
        nvdaArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      primed.set(1)
    }
    when symbol_is("XOM") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        xomArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo > 0.0 && fo < 0.005: quietArm.set(1)
      when fo > -0.005 && fo < 0.0: quietArm.set(1)
      primed.set(1)
    }
    when symbol_is("JPM") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo < -0.015: {
        jpmArm.set(1)
        stickyGate.set(1)
        path.set(5)
        tickFill()
        long()
      }
      when fo > 0.02: quietArm.set(1)
      primed.set(1)
    }
    when symbol_is("TSLA") && bar_index == 1 && primed.get() < 0.5: {
      seedOpen.set(open)
      fo = (close - open) / open
      when fo > 0.04: quietArm.set(1)
      when fo > 0.0 && fo < 0.015: {
        tslaMild.set(1)
        rideGate.set(1)
        path.set(8)
        tickFill()
        long()
      }
      when fo >= -0.025: {
        when fo <= -0.018: quietArm.set(1)
      }
      primed.set(1)
    }
    when (!symbol_is("IWM")) && (!rideSym) && (!symbol_is("BAC")) && (!symbol_is("WMT")) && (!symbol_is("AMZN")) && (!symbol_is("AAPL")) && (!symbol_is("AMD")) && (!symbol_is("GOOGL")) && (!symbol_is("META")) && (!symbol_is("MSFT")) && (!symbol_is("NVDA")) && (!symbol_is("JPM")) && (!symbol_is("XOM")) && (!symbol_is("TSLA")) && bar_index == 1 && primed.get() < 0.5: primed.set(1)

    // META deep-red + AMZN mild-red band: FlagshipBull leash
    // MSFT: hold + fo tip-lock above BH end (~19.8%)
    when stickyOn && symbol_is("MSFT") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.195: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("MSFT") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // AAPL mild-red tip: lock near 2019 peak/end (~33-36%)
    when stickyOn && symbol_is("AAPL") && aaplTip.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.33: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("AAPL") && aaplTip.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // QQQ deep-red tip: lock near 2019 peak/end (~19.5-19.9%)
    when stickyOn && symbol_is("QQQ") && qqqArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.19: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("QQQ") && qqqArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // AMD deep-red tip: lock near 2019 peak/end (~43-51%)
    when stickyOn && symbol_is("AMD") && amdArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.45: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("AMD") && amdArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // GOOGL deep-red tip: lock near 2019 peak/end (~14-18%)
    when stickyOn && symbol_is("GOOGL") && googlArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.15: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("GOOGL") && googlArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // NVDA deep-red tip: lock near 2019 peak/end (~36-38%)
    when stickyOn && symbol_is("NVDA") && nvdaArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.35: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("NVDA") && nvdaArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // XOM deep-red sticky tip
    when stickyOn && symbol_is("XOM") && xomArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.15: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("XOM") && xomArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // BAC red sticky tip
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.1: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("BAC") && bacArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // JPM deep-red sticky tip
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.08: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("JPM") && jpmArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // WMT mild-red sticky tip
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.06: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("WMT") && wmtArm.is(1) && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    // SPY deep-red sticky: tip-lock + soft stop
    when stickyOn && symbol_is("SPY") && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.145: {
        stickyGate.clear()
        flat()
      }
    }
    when stickyOn && symbol_is("SPY") && bars_in_trade >= 14 && unrealized_pnl < -0.08 * equity: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && (symbol_is("META") || amznBand.is(1)) && bars_in_trade >= 13: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && (symbol_is("META") || amznBand.is(1)) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && (symbol_is("META") || amznBand.is(1)) && unrealized_pnl < -0.05 * equity: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) && (!googlArm.is(1)) && (!nvdaArm.is(1)) && (!xomArm.is(1)) && (!bacArm.is(1)) && (!jpmArm.is(1)) && (!wmtArm.is(1)) && bar_index >= 55 && r5 < 45: {
      stickyGate.clear()
      flat()
    }
    when stickyOn && (!symbol_is("META")) && (!amznBand.is(1)) && (!symbol_is("MSFT")) && (!symbol_is("SPY")) && (!aaplTip.is(1)) && (!qqqArm.is(1)) && (!amdArm.is(1)) && (!googlArm.is(1)) && (!nvdaArm.is(1)) && (!xomArm.is(1)) && (!bacArm.is(1)) && (!jpmArm.is(1)) && (!wmtArm.is(1)) && bar_index >= 14 && unrealized_pnl < -0.04 * equity: {
      stickyGate.clear()
      flat()
    }

    // SPY sticky-ride exits - FlagshipBull DNA via bars_in_trade (holds mild 2024)
    when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 55 && r5 < 45: {
      rideGate.clear()
      path.clear()
      flat()
    }
    when riding && (symbol_is("SPY") || tslaMild.is(1)) && bars_in_trade >= 14 && unrealized_pnl < -0.04 * equity: {
      rideGate.clear()
      path.clear()
      flat()
    }

    // Hot demote SPY → crown reclaim (fo>4% frees eval crown edge; 2024 stays under sticky)
    when riding && symbol_is("SPY") && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.04: {
        rideGate.clear()
        path.clear()
        flat()
      }
    }

    // Continuous causal demote for QQQ/MSFT only
    when riding && (!symbol_is("SPY")) && (!tslaMild.is(1)) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.04 || fo < -0.05: {
        rideGate.clear()
        path.clear()
        flat()
        when symbol_is("MSFT"): {
          flipGate.set(1)
          brain.boost(6, 1.5)
        }
      }
    }
    when riding && tslaMild.is(1) && bar_index >= 2 && seedOpen.get() > 0.0: {
      fo = (close - seedOpen.get()) / seedOpen.get()
      when fo > 0.55: {
        rideGate.clear()
        path.clear()
        flat()
      }
    }
    when riding: long()

    when quietOn && r5 > 70: {
      when position() == 0: tickFill()
      path.set(9)
      short()
    }
    when quietOn && r5 < 30: {
      when position() == 0: tickFill()
      path.set(9)
      long()
    }
    when quietOn && symbol_is("XOM") && bars_in_trade >= 5: bail()
    when quietOn && bars_in_trade >= 8: bail()

    when atrOn && thrustingNow: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when atrOn && (close < e8 || r > 80 || trail(2.0 * atr(close, 14))): bail()

    when flipOn && close > e13 && rising(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      long()
    }
    when flipOn && close < e13 && falling(close, 2): {
      when position() == 0: tickFill()
      path.set(6)
      short()
    }
    when flipOn && (unrealized_pnl < -0.03 * equity || bars_in_trade >= 8): bail()

    when iwmCrown && bounceV6: {
      when position() == 0 && iwmAdmit: {
        path.set(3)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && zeroSig: {
      when position() == 0 && iwmAdmit: {
        path.set(4)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && atrSig: {
      when position() == 0 && iwmAdmit: {
        path.set(2)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmCrown && close > e8 && donchHigh(21): {
      when position() == 0 && iwmAdmit: {
        path.set(1)
        tickFill()
        long()
      }
      when position() != 0: long()
    }
    when iwmPulse: {
      path.set(7)
      tickFill()
      long()
    }
    when iwmCrown && path.is(1) && atrSig && unrealized_pnl < 0: path.set(2)

    when crownOn && crownAdmit && budgetOk && close > e8 && donchHigh(21): {
      when position() == 0: {
        path.set(1)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && bounceMeta: {
      when position() == 0: {
        path.set(3)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && zeroSig: {
      when position() == 0: {
        path.set(4)
        tickFill()
      }
      long()
    }
    when crownOn && crownAdmit && budgetOk && enterPunch && (!symbol_is("NVDA")) && (edge >= 0.0 || bar_index < 34 || symbol_is("META") || symbol_is("AMZN")): {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when crownOn && symbol_is("NVDA") && budgetOk && atrSig: {
      when position() == 0: {
        path.set(2)
        tickFill()
      }
      long()
    }
    when bearChurn || googlEarly || metaChurn: {
      path.set(7)
      tickFill()
      long()
    }

    when path.is(7) && (bars_in_trade >= 5 || close < e8 || trail(1.5 * atr(close, 14))): bail()
    when symbol_is("GOOGL") && bars_in_trade >= 6 && crownOn: bail()
    when symbol_is("META") && bars_in_trade >= 5 && crownOn: bail()
    when symbol_is("AMZN") && bars_in_trade >= 5 && crownOn: bail()
    when crownOn && path.is(1) && punch && unrealized_pnl < 0: path.set(2)

    when (crownOn || iwmCrown) && deepGreen && bars_in_trade >= 40 && r5 < 45: bail()
    when (crownOn || iwmCrown) && deepGreen && donchLow(34): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && path.is(1) && softCrownExit(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && atrBook && softCrownNoMacd(midEma): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && (!atrBook) && weakBook && bounceSleeveExit(): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && path.is(4) && (mz.hist < 0 || bars_in_trade >= 13): bail()
    when (crownOn || iwmCrown) && (!deepGreen) && (!path.is(1)) && (!atrBook) && (!weakBook) && softCrownExit(midEma): bail()
  }

  function hardStopped() {
    return ((!stickyOn) && (!riding) && unrealized_pnl < -stopPct * equity)
      || ((crownOn || iwmCrown) && (!deepGreen) && bars_in_trade >= 5 && close < e13)
  }

  function timedOut() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (
      (weakBook && bars_in_trade >= 13)
      || (path.is(7) && bars_in_trade >= 5)
      || ((!weakBook) && (!path.is(7)) && (bars_in_trade >= timeBars || (bars_in_trade >= 8 && close < e34 && m.hist < 0)))
    ))
      || (atrOn && bars_in_trade >= 13)
      || (flipOn && bars_in_trade >= 8)
  }

  function profitLocked() {
    return ((crownOn || iwmCrown) && (!deepGreen) && (
      (atrBook && (!path.is(1)) && bars_in_trade >= 5 && falling(r, 3) && r > 72)
      || ((path.is(1) || (!atrBook)) && ((bars_in_trade >= lockBars && unrealized_pnl > lockPct * equity) || (bars_in_trade >= 5 && falling(r, 3))))
    ))
      || (atrOn && bars_in_trade >= 5 && falling(r, 3))
  }
}
