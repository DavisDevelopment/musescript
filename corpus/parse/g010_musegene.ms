{
  @strategy("musegene")
  @param("p0", 60.319)
  @on(bar) {
    if ((-1.941 <= -0.035)) long(-0.503);
    if (crossover("close", "high")) short(-0.503);
    if (((!((p0 <= low) && (crossover(roc("low", 5), atr("close", 34)) || crossover("high", wma("volume", 21)))))) || ((crossunder(ema("volume", 21), rsi("high", 34)) && crossover(mom("open", 89), ema("high", 34))))) flat();
  }
}