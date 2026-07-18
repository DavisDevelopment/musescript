{
  @strategy("musegene")
  @param("p0", 6.403)
  @param("p1", 26.943)
  @param("p2", 92.11)
  @on(bar) {
    if (crossover(mom("close", 3), highest("low", 89))) long(-1.07);
    if (crossunder(lowest("close", 34), rsi("high", 5))) short(-1.07);
    if ((((p0 > max(open, p1)) || (p2 <= volume))) || (((close + close) < (1.334 * 0.136)))) flat();
  }
}