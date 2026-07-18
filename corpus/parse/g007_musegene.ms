{
  @strategy("musegene")
  @on(bar) {
    if (crossover(sma("open", 89), "volume")) long(min(-0.187, high));
    if (crossover("close", atr("open", 89))) short(min(-0.187, high));
    if (((max(max(-1.802, volume), (volume * low)) > 0.728)) || (crossover(lowest("open", 2), highest("volume", 34)))) flat();
  }
}