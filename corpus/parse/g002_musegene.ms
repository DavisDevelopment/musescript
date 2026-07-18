{
  @strategy("musegene")
  @param("p0", 63.847)
  @param("p1", 86.024)
  @param("p2", 52.575)
  @param("p3", 81.468)
  @param("p4", 87.67)
  @param("p5", 40.667)
  @on(bar) {
    if ((!(!crossover("low", "high")))) long(p5);
    if (((crossover("volume", "open") && (p0 < p1)) && (-0.221 >= open))) short(p5);
    if ((((min(p2, -1.056) >= low) || crossunder(roc("volume", 5), highest("close", 89)))) || ((((crossunder("close", highest("volume", 8)) && crossunder(rma("close", 55), change("volume", 55))) && (p3 < p4)) || (volume <= 0.029)))) flat();
  }
}