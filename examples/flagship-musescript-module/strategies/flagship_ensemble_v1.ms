// Ensemble v1 — regime-gated: a chop/down sleeve (the flagship lineage's validated edge)
// paired with a genuine trend-participation sleeve for strong uptrends, instead of asking
// one system to do both jobs.
//
// Diagnosis this responds to (results/BROAD8MO_REPORT.md): the flagship lineage underperforms
// buy-and-hold specifically in strong-uptrend names (mean d_sharpe -1.19 across 25 broad-universe
// names) while having a REAL edge in down/choppy ones (+0.14 across 12). Reading v6l (the
// best-generalizing version) to design this sleeve surfaced why: its exit logic
// (softCrownExit: RSI(13)>80 or RSI(8)>82 overbought exit, MACD-bear exit, EMA-break exit) plus
// FlagshipRisk's 3%-profit-lock-after-8-bars and 13-bar max hold are textbook short-swing /
// mean-reversion risk management — structurally the wrong tool for trend participation, which
// is exactly where the lineage loses. Also found: much of v6l's apparent sophistication is
// literal per-symbol branching (symbol_is("IWM")/("AAPL")/("MSFT")/("GOOGL")/etc.) that simply
// doesn't exist for any of the 44 symbols outside the original 10-symbol tuning corpus — not a
// regime problem, a "this code has no logic for your ticker" problem. This file has zero
// symbol_is() calls anywhere; every signal here is computable for any instrument.
//
// The regime gate is causal and symbol-agnostic: close above its own EMA AND a positive ROC
// over the trailing lookback. Nothing here needs to know the ticker.
//
// ⚠ UNITS CORRECTION (2026-08-07, comment-only -- behaviour unchanged, all scored results stand).
// This header used to claim the gate is "up >10% over the trailing ~quarter (roc 63 trading
// days)". Both halves were wrong. The lookback is 34 bars, not 63 (see trendRocLen below), and
// MuseScript's roc() returns PERCENTAGE POINTS, not a fraction (TradeBuiltins.hx:773-776 --
// pctChange * 100). So `rocTrend > 0.07` is "up more than 0.07%", i.e. effectively "up at all
// over 34 bars" -- NOT the 7-10% strong-trend filter described. Measured consequence: this
// "confirmed uptrend" sleeve is live on 21% of bars in names that ended the window DOWN >5%.
// Left as-is on purpose: this is the frozen baseline and every number in
// results/BROAD8MO_REPORT.md is quoted against this exact behaviour. Do not "fix" the constant
// without re-baselining -- and note that tightening it does NOT reduce the regime flicker
// (blips get relatively worse; the flicker is the close > eTrend conjunct). See
// harness/diag_regime_units.py.

class FlagshipEnsembleV1 extends muse.Strat {
  param donchIn: Window = 21
  param regimeFloor: Scalar = 0.28
  // 34-bar lookback (not 63) so this warms up with room to trade inside the official ~63-bar
  // eval_3m/wf_2022q1 windows — a 63-day ROC never produces a single valid value in a 63-bar
  // window (needs 63 bars of history just to compute once). Caught by score_probe: 0 trades
  // everywhere on the first attempt, not a real "no signal" result.
  param trendRocLen: Window = 34
  // ⚠ PERCENTAGE POINTS, not a fraction -- this is 0.07%, not 7%. See the units note above.
  param trendRocMin: Scalar = 0.07
  param trendEmaLen: Window = 34

  reg = regimeScore(21)
  e8 = ema(close, 8)
  e13 = ema(close, 13)
  eTrend = ema(close, trendEmaLen)
  rocTrend = roc(close, trendRocLen)
  atr14 = atr(close, 14)

  trendRegime = close > eTrend && rocTrend > trendRocMin

  chopEntry = reg >= regimeFloor && close > e8 && donchHigh(donchIn)
  chopExit = softCrownExit(e13)

  function onBar() {
    // Trend sleeve — enter on a confirmed pullback-recovery, hold through the regime.
    when trendRegime && position() == 0 && close > eTrend && rising(close, 3): long()
    when trendRegime && position() != 0: long()
    // Trend sleeve exit: structure break or a WIDE trailing stop only — no RSI-overbought
    // cut, no short profit-lock. Let a real trend run; only bail on a real break of it.
    when trendRegime && position() != 0 && (close < eTrend || trail(3.0 * atr14)): flat()

    // Chop/down sleeve — the validated edge: donchian-breakout entry gated by regime score,
    // soft-crown exit (this is the sleeve where an RSI-overbought / short-hold exit is the
    // RIGHT tool, because it's not fighting a real trend here).
    when (!trendRegime) && chopEntry: {
      when position() == 0: long()
      when position() != 0: long()
    }
    when (!trendRegime) && position() != 0 && chopExit: flat()
  }

  function hardStopped() {
    return unrealized_pnl < -0.06 * equity
  }

  // Time/profit-lock exits apply ONLY to the chop sleeve on purpose — this is precisely the
  // mechanism that was cutting trend-sleeve winners short in the diagnosed underperformance.
  function timedOut() {
    return (!trendRegime) && bars_in_trade >= 13
  }

  function profitLocked() {
    return (!trendRegime) && bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity
  }

  function onPosition() {
    when hardStopped() || timedOut() || profitLocked(): flat()
  }
}
