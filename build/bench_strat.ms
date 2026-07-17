{
  @strategy("bench")
  @on(bar) {
    if (crossover(sma("close", 10), sma("close", 30)) && (rsi("close", 14) < 70.0)) long();
    if (crossunder(sma("close", 10), sma("close", 30))) flat();
  }
}
