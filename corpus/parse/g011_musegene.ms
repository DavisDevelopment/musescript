{
  @strategy("musegene")
  @on(bar) {
    if ((1.42 <= highest("volume", 5))) long(volume);
    if (crossunder("volume", change("open", 34))) short(volume);
    if (((!((1.327 < open) && crossover("volume", "open")))) || ((crossover(roc("low", 55), "open") && (0.205 >= (-0.739 + low))))) flat();
  }
}