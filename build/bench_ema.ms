{
  @strategy("benchema")
  @on(bar) {
    if (crossover(ema("close", 12), ema("close", 26))) long();
    if (crossunder(ema("close", 12), ema("close", 26))) flat();
  }
}
