// Shock-gated trend — P0 WorldContext seed (aux: world_shock from Jormungandr fan join).
// Desktop embeds the same source in worldMuseBridge.js (SHOCK_GATED_TREND_MS).
{
  @strategy("ShockGatedTrend")
  @param("thresh", 0.08)
  @param("fast", 3)
  @param("slow", 7)
  @on(bar) {
    if (!na(world_shock) && world_shock > thresh && sma(close, fast) > sma(close, slow)) long();
    if (na(world_shock) || world_shock < thresh * 0.4 || sma(close, fast) < sma(close, slow)) flat();
  }
}
