{
  @strategy("musegene")
  @on(bar) {
    if ((max(close, (1.604 - close)) >= min(0.296, high))) long(volume);
    if ((min(open, volume) < -1.471)) short(volume);
    if (((!crossover(rsi("high", 13), "high"))) || ((atr("close", 13) < rsi("low", 3)))) flat();
  }
}