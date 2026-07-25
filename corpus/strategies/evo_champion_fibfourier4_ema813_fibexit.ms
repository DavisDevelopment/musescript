strategy S02_Ema813Ex21 {
  onBar {
    when crossover(ema("close", 8), ema("close", 13)) && position() <= 0:
      { long(1) }
    when crossunder(rma("high", 13), ema("high", 89)) && position() >= 0:
      { short(1) }
    when (low > stoch(14, 3, 3).k) || ((close > fib_retracement(100).level500) && (rsi("close", 13) > 68 || unrealized_pnl_pct() < -0.02)):
      { flat() }
  }
}

/* CORPUS_BACKTEST
  pulled from: build/graal/fibfourier_run4.log, corpus-evo GraalWasm run, seed=42 pop=80 gens=30, cost=20bps
  lineage: b87854ff324fe8fc <- c9a95616fbbc69df <- 6837a6bcd0a9c9f0
  IS (in-sample, nvda.csv minus embargo tail): fitness(sharpe-with-parsimony)=0.8151 sharpe=0.8251 trades=143 finalEquity=100009.28 nodeCount=21
  OOS re-score (held-out 1727-bar tail): sharpe=-0.4413 trades=116 [did NOT hold] -- this exact top-fitness individual overfit; siblings 3 ranks lower on IS (fitness=0.7938) held OOS at sharpe=0.046
*/
