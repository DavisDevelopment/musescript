// Flagship v1 — crown DNA + soft exits (promoted from Stage A/B probes).
//
// Evidence vs v0 (causal 10bps next-open):
//   liquid10 eval_3m: 5/10 → 6/10 (SPY/AMD/GOOGL flipped; exit-tune lifts mean score)
//   liquid10 wf_2022q1: 0/10 → 8/10
//   chip2: 2/2 perfect
// Rejected: naive short sleeves, SMA34 hard-gate, loose regime OR-hybrid on bull tape
//
// Remaining weak: IWM / AAPL / MSFT / META (eval_3m), AMD+AMZN (2022), swing band.

class FlagshipV1 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param slowEma: Window = 34 { min: 21, max: 55, step: 13, tune: grid }
  param bearCut: Scalar = 0.20 { min: 0.12, max: 0.28, step: 0.04, tune: grid }

  r = rsi(close, 13)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, slowEma)
  gate = sma(close, slowEma)
  reg = regimeScore(21)

  function onBar() {
    when close > eFast && donchHigh(donchIn): long()
    when reg < bearCut && macdBear(13, 34, 8) && rising(m.hist, 3) && close > gate: long()
    when softCrownExit(midEma): flat()
  }

  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < eMid)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < eSlow && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (bars_in_trade >= 5 && falling(r, 3))
  }
}

pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, fastEma, midEma, stopPct, timeBars, bearCut)
  optimize(sharpe)
}
