{
  @strategy("musegene")
  @param("p0", 48.593)
  @param("p1", 82.985)
  @param("p2", 39.882)
  @param("p3", 92.308)
  @on(bar) {
    if ((((p0 >= p1) && (!crossover(wma("high", 3), wma("volume", 5)))) || crossover(roc("low", 55), rma("close", 21)))) long((p3 + -0.435));
    if ((min(0.085, volume) < (p2 + (1.312 + low)))) short((p3 + -0.435));
    if (((crossover("high", highest("open", 3)) && (!((volume <= open) || (max(-0.849, close) < high))))) || (crossover(sma("volume", 13), ema("high", 5)))) flat();
  }
}