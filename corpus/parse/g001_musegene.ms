{
  @strategy("musegene")
  @param("p0", 50.528)
  @on(bar) {
    if (crossover("close", highest("close", 8))) long(close);
    if (crossover(stdev("close", 2), wma("high", 3))) short(close);
    if (((crossover(sma("close", 8), change("open", 89)) || crossunder(lowest("high", 21), "high"))) || (((!(!crossover("low", "low"))) && ((!(1.641 <= low)) || (p0 <= -1.862))))) flat();
  }
}