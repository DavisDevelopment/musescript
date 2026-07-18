{
  @strategy("musegene")
  @param("p0", 45.913)
  @on(bar) {
    if (crossunder("open", "high")) long(0.229);
    if (((p0 <= -0.02) || crossunder("high", change("low", 89)))) short(0.229);
    if ((((open * close) <= high)) || (((-1.431 < open) && (volume < 0.337)))) flat();
  }
}