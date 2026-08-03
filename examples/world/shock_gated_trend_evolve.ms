// Shock-gated trend (evolvable) — P2 WorldContext seed with @param ranges.
// Desktop embeds SHOCK_GATED_TREND_EVOLVE_MS in worldMuseBridge.js.
{
  @strategy("ShockGatedTrendEvolve")
  @param("thresh", 0.08) { min: 0.02, max: 0.35, step: 0.06, tune: "grid" }
  @param("fast", 3) { min: 2, max: 5, step: 1, tune: "grid" }
  @param("slow", 7) { min: 5, max: 11, step: 2, tune: "grid" }
  @on(bar) {
    if (!na(world_shock) && world_shock > thresh && sma(close, fast) > sma(close, slow)) long();
    if (na(world_shock) || world_shock < thresh * 0.4 || sma(close, fast) < sma(close, slow)) flat();
  }
}
