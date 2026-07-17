{
  @strategy("instr")
  @on(bar) {
    plot(sma("close", 10), "sma10");
    if (crossover(sma("close", 5), sma("close", 20))) { log("entry", close); long(); }
    if (crossunder(sma("close", 5), sma("close", 20))) { log("exit"); flat(); }
  }
}
