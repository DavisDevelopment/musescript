{
  @strategy("musegene")
  @param("p0", 69.791)
  @on(bar) {
    if ((((high >= -0.119) || (crossover("high", stdev("volume", 89)) && (0.798 < max(1.377, open)))) && (min(1.022, 1.186) <= open))) long(high);
    if (((1.331 * volume) < p0)) short(high);
    if ((((!crossunder("high", "volume")) || (-1.641 >= max(volume, -0.751)))) || (crossunder("volume", "volume"))) flat();
  }
}