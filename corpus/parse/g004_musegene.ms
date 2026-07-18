{
  @strategy("musegene")
  @param("p0", 19.344)
  @on(bar) {
    if (crossover(highest("high", 3), "close")) long(0.396);
    if (((volume + high) >= (open * (p0 * low)))) short(0.396);
    if ((crossunder(lowest("high", 5), "low")) || (crossunder("low", wma("volume", 8)))) flat();
  }
}