// Flagship v0 — metaprogrammed RSI-crown Donchian.
// Stitched with lib/*.ms by harness/eval.py before gene-runner sees it.
//
// Metaprogramming surface:
//   - class FlagshipV0 extends FlagshipRisk (ClassStrategyLower + super helpers)
//   - expr templates (donchHigh / crownExit / …) from lib
//   - indicator function regimeScore
//   - param { min, max, step, tune: grid } search holes
//   - pipeline Discover { walkforward, promote, tune, optimize }
//
// Note: stmt-template SoftStop / module `use RiskKit` expand inside `strategy { }`
// bodies, not class fields — RiskKit lives in lib for strategy-form variants;
// this class owns risk via FlagshipRisk + super.*.

class FlagshipV0 extends FlagshipRisk {
  param donchIn: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param fastEma: Window = 8 { min: 5, max: 13, step: 3, tune: grid }
  param midEma: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param slowEma: Window = 34 { min: 21, max: 55, step: 13, tune: grid }
  param rsiLen: Window = 13 { min: 8, max: 21, step: 5, tune: grid }
  param bbLen: Window = 21 { min: 13, max: 34, step: 8, tune: grid }
  param regimeFloor: Scalar = 0.22 { min: 0.15, max: 0.30, step: 0.05, tune: grid }

  r = rsi(close, rsiLen)
  m = macd(close, 13, 34, 8)
  eFast = ema(close, fastEma)
  eMid = ema(close, midEma)
  eSlow = ema(close, slowEma)
  bb = bbands(close, bbLen, 2.0)
  reg = regimeScore(21)

  function onBar() {
    if (crownExit(midEma) || reg < regimeFloor) {
      flat()
    } else if (close > eFast && donchHigh(donchIn)) {
      long()
    } else {
      when falling(r, 3, 5): flat()
    }
  }

  // Extend inherited stop helpers (super.* only legal inside the override itself).
  function hardStopped() {
    return super.hardStopped() || (bars_in_trade >= 5 && close < eMid)
  }

  function timedOut() {
    return super.timedOut() || (bars_in_trade >= 8 && close < eSlow && m.hist < 0)
  }

  function profitLocked() {
    return super.profitLocked() || (close >= bb.upper && unrealized_pnl > 0) || falling(r, 3)
  }
}

// Discovery metaprogram — MusePlanner → PlanRunner / HonestOptimize.
// Walk-forward trains per fold; promote() gates on aggregate OOS metrics only.
pipeline Discover {
  walkforward(3, 5)
  promote((r) => r.sharpe > 0.0 && r.maxDrawdown < 0.25 && r.trades >= 2)
  tune(donchIn, fastEma, midEma, stopPct, timeBars, regimeFloor)
  optimize(sharpe)
}
