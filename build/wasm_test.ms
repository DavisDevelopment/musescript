{
  @strategy("wasmtest")
  @on(bar) {
    if (crossover(sma("close", 5), sma("close", 20))) long();
    if (crossunder(sma("close", 5), sma("close", 20))) flat();
  }
}
