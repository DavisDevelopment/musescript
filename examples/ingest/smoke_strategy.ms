# Post-ingest offline strategy — run with grants null / GeneRunner --tape
@strategy("ingest_smoke")
@on(bar) {
  if (close > open) long();
  else if (close < open) flat();
}
