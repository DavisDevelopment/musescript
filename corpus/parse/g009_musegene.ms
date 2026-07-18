{
  @strategy("musegene")
  @param("p0", 45.202)
  @param("p1", 20.496)
  @param("p2", 0.387)
  @param("p3", 19.767)
  @param("p4", 9.342)
  @param("p5", 12.134)
  @on(bar) {
    if ((open >= mom("open", 21))) long(-0.391);
    if (((p0 - (open - volume)) > max(close, (p1 + close)))) short(-0.391);
    if (((((crossunder(atr("open", 34), "close") || (close < (p2 + p3))) && (crossover("open", mom("close", 89)) || (high <= p4))) || ((volume + 1.408) < max(p5, 1.804)))) || (crossover(roc("volume", 3), ema("volume", 21)))) flat();
  }
}